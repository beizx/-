import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/tts_settings.dart';
import '../services/reader/speech_engine.dart';
import '../services/reader/tts_media_session.dart';

enum TtsStatus { idle, playing, paused, error }

/// One utterance: a paragraph, or a sentence-sized slice of a long paragraph.
///
/// [start] / [end] point into the chapter's raw text so the reader can
/// highlight exactly what is being spoken.
class TtsSegment {
  const TtsSegment({
    required this.text,
    required this.start,
    required this.end,
    required this.paragraphIndex,
  });

  final String text;
  final int start;
  final int end;
  final int paragraphIndex;
}

/// Drives 听书 playback for one book.
///
/// Design notes:
/// - Speech is split per paragraph/sentence, not per chapter: pause, skip and
///   highlight stay responsive and the platform queue never overflows.
/// - The controller owns the book and chapter cursor, so "自动下一章" works even
///   when the reader page has been closed (the notification-style player keeps
///   running until stopped).
class TtsController extends ChangeNotifier {
  TtsController({
    SpeechEngine? engine,
    TtsPreferences preferences = const TtsPreferences(),
    TtsMediaSession? mediaSession,
  }) : _engine = engine ?? FlutterTtsEngine(),
       _preferences = preferences.normalized(),
       _mediaSession = mediaSession {
    _engine.setHandlers(onComplete: _handleSegmentComplete);
    mediaSession?.bindCommands(
      TtsMediaCommands(
        onPlay: _handleRemotePlay,
        onPause: _handleRemotePause,
        onStop: stop,
        onNext: _handleRemoteNextChapter,
        onPrevious: _handleRemotePreviousChapter,
      ),
    );
  }

  /// Longest utterance; long Chinese paragraphs split at punctuation.
  static const maxSegmentLength = 220;

  final SpeechEngine _engine;

  /// Lock screen / notification / headset bridge; null in tests and on
  /// platforms without a media session.
  final TtsMediaSession? _mediaSession;
  TtsMediaInfo? _lastMediaInfo;

  TtsPreferences _preferences;
  Book? _book;
  int _chapterIndex = 0;
  List<TtsSegment> _segments = const [];
  int _segmentIndex = 0;
  TtsStatus _status = TtsStatus.idle;
  String? _error;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  int _sleepMinutes = 0;
  bool _sleepAtChapterEnd = false;
  bool _disposed = false;

  TtsPreferences get preferences => _preferences;
  Book? get book => _book;
  int get chapterIndex => _chapterIndex;
  String? get chapterTitle {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return null;
    return book.chapters[_chapterIndex.clamp(0, book.chapters.length - 1)].title;
  }

  TtsStatus get status => _status;
  String? get error => _error;
  bool get isPlaying => _status == TtsStatus.playing;
  bool get isPaused => _status == TtsStatus.paused;
  bool get isActive => _status == TtsStatus.playing || _status == TtsStatus.paused;
  bool get hasContent => _segments.isNotEmpty;

  int get segmentIndex => _segmentIndex;
  int get segmentCount => _segments.length;
  DateTime? get sleepDeadline => _sleepDeadline;
  int get sleepMinutes => _sleepMinutes;
  bool get sleepAtChapterEnd => _sleepAtChapterEnd;

  /// Sets the 定时关闭 mode. `minutes == 0` turns the timer off.
  void setSleepTimer({int minutes = 0, bool atChapterEnd = false}) {
    _sleepMinutes = minutes.clamp(0, 120);
    _sleepAtChapterEnd = atChapterEnd;
    _restartSleepTimer();
    if (!_disposed) notifyListeners();
  }

  /// Text of the utterance being spoken, used for the reader highlight.
  String? get activeText =>
      _segments.isEmpty ? null : _segments[_segmentIndex].text;

  int? get activeParagraphIndex =>
      _segments.isEmpty ? null : _segments[_segmentIndex].paragraphIndex;

  double get chapterProgress => _segments.isEmpty
      ? 0
      : ((_segmentIndex + 1) / _segments.length).clamp(0.0, 1.0);

  /// True when the controller is reading [chapterIndex] of [bookId].
  bool isReadingChapter(String bookId, int chapterIndex) {
    return isActive &&
        _book?.id == bookId &&
        _chapterIndex == chapterIndex;
  }

  Future<void> updatePreferences(TtsPreferences preferences) async {
    final next = preferences.normalized();
    if (next == _preferences) return;
    _preferences = next;
    notifyListeners();
    if (isPlaying) {
      await _engine.prepare(_preferences);
    }
  }

  Future<List<TtsVoiceInfo>> availableVoices() => _engine.voices();

  bool get canSkipPreviousChapter => _book != null && _chapterIndex > 0;

  bool get canSkipNextChapter {
    final book = _book;
    return book != null && _chapterIndex < book.chapters.length - 1;
  }

  /// Mirrors the session into the OS media UI.
  ///
  /// Equality on [TtsMediaInfo] keeps per-sentence progress from spamming the
  /// platform channel: only real changes (chapter, play state) are published.
  void _publishMedia() {
    final session = _mediaSession;
    if (session == null) return;
    final book = _book;
    if (book == null) {
      if (_lastMediaInfo == null) return;
      _lastMediaInfo = null;
      unawaited(session.clear());
      return;
    }
    final info = TtsMediaInfo(
      bookTitle: book.meta.title,
      chapterTitle: chapterTitle ?? book.meta.title,
      isPlaying: _status == TtsStatus.playing,
      canSkipPrevious: canSkipPreviousChapter,
      canSkipNext: canSkipNextChapter,
    );
    if (info == _lastMediaInfo) return;
    _lastMediaInfo = info;
    unawaited(session.update(info));
  }

  Future<void> _handleRemotePlay() async {
    switch (_status) {
      case TtsStatus.paused:
        await resume();
      case TtsStatus.error:
        final book = _book;
        if (book != null) await startChapter(book, _chapterIndex);
      case TtsStatus.playing:
      case TtsStatus.idle:
        break;
    }
  }

  Future<void> _handleRemotePause() => pause();

  Future<void> _handleRemoteNextChapter() => skipChapter(1);

  Future<void> _handleRemotePreviousChapter() => skipChapter(-1);

  /// Starts (or restarts) playback from the reader's current position.
  Future<void> startChapter(
    Book book,
    int chapterIndex, {
    double chapterFraction = 0,
  }) async {
    if (book.chapters.isEmpty) return;
    final index = chapterIndex.clamp(0, book.chapters.length - 1);
    final chapter = book.chapters[index];
    final segments = buildSegments(chapter.text);
    if (segments.isEmpty) {
      _error = '这一章没有可以朗读的文字';
      _status = TtsStatus.error;
      notifyListeners();
      _publishMedia();
      return;
    }

    _book = book;
    _chapterIndex = index;
    _segments = segments;
    _error = null;
    _restartSleepTimer();

    // Resume from the visible page instead of chapter start.
    _segmentIndex = _segmentForFraction(chapterFraction, segments.length);
    await _play();
  }

  Future<void> toggle() async {
    switch (_status) {
      case TtsStatus.playing:
        await pause();
      case TtsStatus.paused:
        await resume();
      case TtsStatus.error:
        if (_book != null) {
          await startChapter(_book!, _chapterIndex, chapterFraction: 0);
        }
      case TtsStatus.idle:
        break;
    }
  }

  Future<void> pause() async {
    if (_status != TtsStatus.playing) return;
    await _engine.pause();
    _status = TtsStatus.paused;
    if (!_disposed) notifyListeners();
    _publishMedia();
  }

  Future<void> resume() async {
    if (_status != TtsStatus.paused || _segments.isEmpty) return;
    await _play();
  }

  Future<void> stop() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    await _engine.stop();
    _segments = const [];
    _segmentIndex = 0;
    _chapterIndex = 0;
    _book = null;
    if (_status != TtsStatus.idle) {
      _status = TtsStatus.idle;
      if (!_disposed) notifyListeners();
    }
    _publishMedia();
  }

  /// Skips one utterance; crosses into adjacent chapters at the edges.
  Future<void> skipSegment(int delta) async {
    if (_segments.isEmpty) return;
    final target = _segmentIndex + delta;
    if (target < 0) {
      if (_chapterIndex > 0) {
        await _jumpChapter(_chapterIndex - 1, fromEnd: true);
      }
      return;
    }
    if (target >= _segments.length) {
      await _advanceChapter();
      return;
    }
    _segmentIndex = target;
    await _play();
  }

  Future<void> skipChapter(int delta) async {
    final book = _book;
    if (book == null) return;
    final target = _chapterIndex + delta;
    if (target < 0 || target >= book.chapters.length) return;
    await _jumpChapter(target);
  }

  Future<void> _jumpChapter(int index, {bool fromEnd = false}) async {
    final book = _book;
    if (book == null) return;
    final chapter = book.chapters[index];
    final segments = buildSegments(chapter.text);
    if (segments.isEmpty) {
      _error = '这一章没有可以朗读的文字';
      _status = TtsStatus.error;
      if (!_disposed) notifyListeners();
      _publishMedia();
      return;
    }
    _chapterIndex = index;
    _segments = segments;
    _segmentIndex = fromEnd ? segments.length - 1 : 0;
    _error = null;
    await _play();
  }

  Future<void> _advanceChapter() async {
    final book = _book;
    if (book == null) return;
    final hasNext = _chapterIndex < book.chapters.length - 1;
    if (!hasNext || !_preferences.autoNextChapter) {
      await _finishPlayback();
      return;
    }
    await _jumpChapter(_chapterIndex + 1);
  }

  Future<void> _finishPlayback() async {
    await _engine.stop();
    _status = TtsStatus.idle;
    _segmentIndex = 0;
    if (!_disposed) notifyListeners();
    _publishMedia();
  }

  Future<void> _play() async {
    if (_segments.isEmpty) return;
    _status = TtsStatus.playing;
    if (!_disposed) notifyListeners();
    _publishMedia();
    try {
      await _engine.prepare(_preferences);
      await _engine.speak(_segments[_segmentIndex].text);
    } on Object catch (error) {
      _error = '朗读引擎出错了：$error';
      _status = TtsStatus.error;
      if (!_disposed) notifyListeners();
      _publishMedia();
    }
  }

  void _handleSegmentComplete() {
    if (_disposed || _status != TtsStatus.playing) return;
    if (_segmentIndex < _segments.length - 1) {
      _segmentIndex++;
      unawaited(_play());
      return;
    }
    if (_sleepAtChapterEnd || _sleepDeadlineReached) {
      unawaited(_finishPlayback());
      return;
    }
    unawaited(_advanceChapter());
  }

  bool get _sleepDeadlineReached {
    final deadline = _sleepDeadline;
    return deadline != null && !DateTime.now().isBefore(deadline);
  }

  void _restartSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    if (_sleepMinutes <= 0) return;

    final duration = Duration(minutes: _sleepMinutes);
    _sleepDeadline = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      _sleepDeadline = null;
      unawaited(_finishPlayback());
    });
  }

  static int _segmentForFraction(double fraction, int count) {
    if (count <= 0) return 0;
    if (fraction <= 0) return 0;
    return ((fraction * count).floor()).clamp(0, count - 1);
  }

  /// Splits a chapter into utterances. ASCII/Latin text splits on sentence
  /// punctuation too, so long English paragraphs stay snappy.
  static List<TtsSegment> buildSegments(String chapterText) {
    final normalized = chapterText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final segments = <TtsSegment>[];
    var cursor = 0;
    var paragraphIndex = 0;

    for (final rawLine in normalized.split('\n')) {
      final lineStart = cursor;
      cursor += rawLine.length + 1;
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;
      final leading = rawLine.indexOf(trimmed);
      final base = lineStart + (leading < 0 ? 0 : leading);

      for (final slice in _splitLongText(trimmed)) {
        final offset = slice.offsetInParagraph.clamp(0, trimmed.length);
        segments.add(
          TtsSegment(
            text: slice.text,
            start: base + offset,
            end: base + offset + slice.text.length,
            paragraphIndex: paragraphIndex,
          ),
        );
      }
      paragraphIndex++;
    }
    return segments;
  }

  static const _sentenceStops = {
    '。',
    '！',
    '？',
    '；',
    '…',
    '!',
    '?',
    ';',
    '.',
    '\n',
  };

  static List<_Slice> _splitLongText(String paragraph) {
    if (paragraph.length <= maxSegmentLength) {
      return [_Slice(text: paragraph, offsetInParagraph: 0)];
    }
    final slices = <_Slice>[];
    var start = 0;
    while (start < paragraph.length) {
      var end = (start + maxSegmentLength).clamp(0, paragraph.length);
      if (end < paragraph.length) {
        final window = paragraph.substring(start, end);
        var cut = -1;
        for (var i = window.length - 1; i >= 0; i--) {
          if (_sentenceStops.contains(window[i])) {
            cut = start + i + 1;
            break;
          }
        }
        // Give up on punctuation for pathological text (no stops at all) and
        // cut at the hard limit instead of producing one huge utterance.
        end = cut > start + 20 ? cut : end;
      }
      final slice = paragraph.substring(start, end);
      if (slice.trim().isNotEmpty) {
        slices.add(_Slice(text: slice, offsetInParagraph: start));
      }
      if (end <= start) break;
      start = end;
    }
    return slices;
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepTimer?.cancel();
    _engine.setHandlers();
    unawaited(_engine.stop());
    final session = _mediaSession;
    if (session != null && _lastMediaInfo != null) {
      _lastMediaInfo = null;
      unawaited(session.clear());
    }
    super.dispose();
  }
}

class _Slice {
  const _Slice({required this.text, required this.offsetInParagraph});

  final String text;
  final int offsetInParagraph;
}
