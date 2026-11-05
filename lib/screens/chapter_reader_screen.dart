import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/text_utils.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/reader_settings.dart';
import '../services/reader/background_playback_guide.dart';
import '../services/reader/reader_system.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../state/tts_controller.dart';
import '../widgets/reader_content.dart';
import '../widgets/reader_contents_sheet.dart';
import '../widgets/reader_settings_panel.dart';
import '../widgets/tts_player_sheet.dart';

/// Immersive novel reader.
///
/// Two reading modes share one chrome: a vertical scroll mode and a paginated
/// page-turn mode. Reading position, reading time and bookmarks are persisted
/// locally, and the original / translation switch stays available when a
/// translation record exists.
class ChapterReaderScreen extends StatefulWidget {
  const ChapterReaderScreen({
    super.key,
    required this.book,
    required this.initialChapterIndex,
    this.translation,
  });

  final Book book;
  final int initialChapterIndex;
  final TranslationRecord? translation;

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen>
    with WidgetsBindingObserver {
  late int _index;
  late final PageController _chapterController;
  late final ValueNotifier<double> _fraction;

  ReaderPreferences _reader = const ReaderPreferences();
  SettingsController? _settings;
  LibraryController? _library;
  TtsController? _tts;
  bool _showTranslation = false;
  bool _chromeVisible = false;
  bool _initialized = false;
  bool _counting = true;
  bool _bookmarkBusy = false;
  int _sessionSeconds = 0;
  int _positionToken = 0;
  DateTime _now = DateTime.now();
  DateTime? _lastPersist;
  Timer? _ticker;

  /// Memoised reading surface. Rebuilding an unchanged subtree is the main
  /// source of dropped frames while scrolling, so the widget instance is
  /// reused whenever nothing that affects layout has changed.
  Widget? _contentCache;
  String? _contentCacheKey;

  /// Sentence being spoken, delivered outside the widget cache so 听书 does not
  /// rebuild the chapter on every utterance.
  final ValueNotifier<String?> _highlight = ValueNotifier<String?>(null);
  final ReaderNavigationHandle _navigation = ReaderNavigationHandle();
  final FocusNode _readerFocus = FocusNode(debugLabel: 'reader');
  DateTime? _lastVolumeAt;
  int? _lastVolumeDirection;
  bool _volumeCapture = false;
  bool _shownTtsFailureGuide = false;

  @override
  void initState() {
    super.initState();
    final lastIndex = widget.book.chapters.isEmpty
        ? 0
        : widget.book.chapters.length - 1;
    _index = widget.initialChapterIndex.clamp(0, lastIndex);
    _chapterController = PageController(initialPage: _index);
    _fraction = ValueNotifier<double>(0);
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
    ReaderSystem.bindVolumeKeys(_onVolumeKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _settings = Provider.of<SettingsController?>(context, listen: false);
    _library = Provider.of<LibraryController?>(context, listen: false);
    _tts = Provider.of<TtsController?>(context, listen: false);
    _tts?.addListener(_handleTtsChanged);
    _reader = _settings?.readerPreferences ?? const ReaderPreferences();
    final progress = _library?.progressFor(widget.book.id);
    if (progress != null && progress.chapterIndex == _index) {
      _fraction.value = progress.safeChapterFraction;
    }
    unawaited(ReaderSystem.keepScreenOn(_reader.keepScreenOn));
    _applySystemUi(_reader);
  }

  /// Follows the audiobook: when TTS advances into another chapter the reader
  /// scrolls along, and playback keeps the screen awake.
  void _handleTtsChanged() {
    final tts = _tts;
    if (tts == null || !mounted) return;
    final wasPlaying = _wasTtsPlaying;
    _wasTtsPlaying = tts.isPlaying;

    if (tts.book?.id != widget.book.id) {
      _syncHighlight();
      return;
    }
    if (tts.isActive && tts.chapterIndex != _index) {
      final target = tts.chapterIndex.clamp(0, _chapterCount - 1);
      setState(() {
        _index = target;
        _positionToken++;
      });
      if (_chapterController.hasClients) {
        _chapterController.jumpToPage(target);
      }
      unawaited(_persistProgress(force: true));
      HapticFeedback.selectionClick();
      _syncHighlight();
      return;
    }

    _syncHighlight();
    if (tts.isPlaying || wasPlaying) {
      unawaited(ReaderSystem.keepScreenOn(true));
    }
    // Only the 听书 button state depends on play/pause; the spoken sentence is
    // pushed through [_highlight] so the chapter itself is never rebuilt.
    if (tts.isPlaying != wasPlaying) setState(() {});
    if (tts.status == TtsStatus.error && !_shownTtsFailureGuide) {
      _shownTtsFailureGuide = true;
      unawaited(_maybeShowBackgroundGuide(becauseFailed: true));
    }
  }

  void _syncHighlight() {
    final next = _ttsHighlight;
    if (next == _highlight.value) return;
    _highlight.value = next;
  }

  bool _wasTtsPlaying = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _counting = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persistProgress(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tts?.removeListener(_handleTtsChanged);
    _ticker?.cancel();
    unawaited(_persistProgress(force: true));
    unawaited(ReaderSystem.keepScreenOn(false));
    if (_volumeCapture) {
      unawaited(ReaderSystem.setVolumeKeyCapture(false));
    }
    ReaderSystem.bindVolumeKeys(null);
    _restoreSystemChrome();
    _chapterController.dispose();
    _fraction.dispose();
    _highlight.dispose();
    _readerFocus.dispose();
    super.dispose();
  }

  int get _chapterCount => widget.book.chapters.length;

  BookChapter get _chapter => widget.book.chapters[_index];

  bool get _hasTranslation => widget.translation != null;

  ReaderPreferences get _readerPrefs => _reader;

  void _tick(Timer timer) {
    if (!mounted) return;
    if (_counting) {
      _sessionSeconds++;
      if (_sessionSeconds > 0 && _sessionSeconds % 60 == 0) {
        unawaited(_persistProgress(force: true));
      }
    }
    final now = DateTime.now();
    if (now.minute != _now.minute) {
      setState(() => _now = now);
    }
  }

  Future<void> _persistProgress({bool force = false}) async {
    final library = _library;
    if (library == null || _chapterCount == 0) return;
    final now = DateTime.now();
    if (!force &&
        _lastPersist != null &&
        now.difference(_lastPersist!) < const Duration(seconds: 3)) {
      return;
    }
    _lastPersist = now;
    final seconds = _sessionSeconds;
    _sessionSeconds = 0;
    await library.saveProgress(
      widget.book.id,
      _index,
      chapterFraction: _fraction.value,
      addReadingSeconds: seconds,
    );
  }

  void _onFractionChanged(int index, double fraction) {
    if (index != _index) return;
    final next = fraction.clamp(0.0, 1.0);
    if ((next - _fraction.value).abs() < 0.0005) return;
    _fraction.value = next;
    unawaited(_persistProgress());
  }

  void _onSwipeChapter(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _fraction.value = 0;
    _syncHighlight();
    HapticFeedback.selectionClick();
    unawaited(_persistProgress(force: true));
  }

  void _goToChapter(int index, {bool toStart = true}) {
    if (index < 0 || index >= _chapterCount || index == _index) return;
    HapticFeedback.selectionClick();
    if (_readerPrefs.mode == ReaderMode.scroll &&
        _chapterController.hasClients) {
      if ((index - _index).abs() == 1) {
        _chapterController.animateToPage(
          index,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } else {
        // A long jump (table of contents) should not animate through every
        // intermediate chapter or we would record them as read.
        _chapterController.jumpToPage(index);
      }
      return;
    }
    setState(() {
      _index = index;
      _positionToken++;
      _fraction.value = toStart ? 0 : 0.999;
    });
    _syncHighlight();
    unawaited(_persistProgress(force: true));
  }

  void _jumpToBookmark(Bookmark bookmark) {
    if (_chapterCount == 0) return;
    final target = bookmark.chapterIndex.clamp(0, _chapterCount - 1);
    setState(() {
      _index = target;
      _positionToken++;
      _fraction.value = bookmark.fraction;
    });
    _syncHighlight();
    if (_chapterController.hasClients) {
      _chapterController.jumpToPage(target);
    }
    unawaited(_persistProgress(force: true));
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    _applySystemUi(_readerPrefs);
  }

  void _applySystemUi(ReaderPreferences reader) {
    final hideStatusBar = !_chromeVisible && reader.hideStatusBar;
    SystemChrome.setEnabledSystemUIMode(
      hideStatusBar ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _restoreSystemChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _applyReader(ReaderPreferences next) {
    setState(() => _reader = next);
    final settings = _settings;
    if (settings != null) {
      unawaited(settings.setReaderPreferences(next));
    }
    unawaited(ReaderSystem.keepScreenOn(next.keepScreenOn));
    _applySystemUi(next);
  }

  String _textFor(int index, BookChapter chapter) {
    if (!_showTranslation) return chapter.text;
    return widget.translation?.chapterFor(chapter.id)?.text ?? '';
  }

  String get _currentText => _textFor(_index, _chapter);

  String _snippetAt(double fraction) {
    final text = _currentText;
    if (text.trim().isEmpty) return '';
    final start = ((fraction * text.length).round())
        .clamp(0, math.max(text.length - 1, 0))
        .toInt();
    var chunk = text.substring(start, math.min(text.length, start + 200));
    if (chunk.trim().isEmpty) chunk = text;
    return excerpt(chunk);
  }

  Future<void> _toggleBookmark() async {
    final library = _library;
    if (library == null || _bookmarkBusy) return;
    _bookmarkBusy = true;
    try {
      final existing = library.bookmarkNear(
        widget.book.id,
        _index,
        _fraction.value,
      );
      if (existing != null) {
        await library.removeBookmark(existing.id);
        if (mounted) _showMessage('已移除这枚书签');
        return;
      }
      final bookmark = Bookmark.create(
        bookId: widget.book.id,
        chapterIndex: _index,
        chapterTitle: _chapter.title,
        fraction: _fraction.value,
        snippet: _snippetAt(_fraction.value),
      );
      await library.addBookmark(bookmark);
      if (mounted) _showMessage('已把这一段收进书签');
    } finally {
      _bookmarkBusy = false;
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  Future<void> _openChapters() async {
    if (_chapterCount == 0) return;
    HapticFeedback.selectionClick();
    final library = _library;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => ReaderContentsSheet(
        book: widget.book,
        currentChapterIndex: _index,
        translation: widget.translation,
        bookmarks: library?.bookmarksFor(widget.book.id) ?? const [],
        onSelectChapter: (index) => _goToChapter(index),
        onSelectBookmark: _jumpToBookmark,
        onDeleteBookmark: (bookmark) async {
          await library?.removeBookmark(bookmark.id);
        },
      ),
    );
  }

  Future<void> _openTtsPlayer() async {
    final tts = _tts;
    if (tts == null) {
      if (mounted) _showMessage('听书功能初始化失败');
      return;
    }
    if (!tts.isReadingChapter(widget.book.id, _index)) {
      final settings = _settings;
      if (settings != null) {
        await tts.updatePreferences(settings.ttsPreferences);
      }
      await tts.startChapter(
        widget.book,
        _index,
        chapterFraction: _fraction.value,
      );
      if (mounted) await _maybeShowBackgroundGuide();
    }
    if (!mounted) return;
    await showTtsPlayerSheet(context, book: widget.book);
  }

  Future<void> _openReaderSettings() async {
    HapticFeedback.selectionClick();
    var current = _readerPrefs;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.84,
          child: SafeArea(
            top: false,
            child: ReaderSettingsPanel(
              preferences: current,
              onChanged: (next) {
                setSheetState(() => current = next);
                _applyReader(next);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _toggleTranslation() {
    setState(() => _showTranslation = !_showTranslation);
    HapticFeedback.selectionClick();
    unawaited(_persistProgress(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController?>();
    final reader = settings?.readerPreferences ?? _reader;
    _reader = reader;
    final skin = reader.skin;
    final inset = MediaQuery.paddingOf(context);
    final indicatorsEnabled =
        reader.showClock || reader.showChapterTitle || reader.showProgress;
    final contentPadding = EdgeInsets.fromLTRB(
      inset.left + reader.horizontalMargin,
      inset.top + reader.topMargin,
      inset.right + reader.horizontalMargin,
      inset.bottom + reader.bottomMargin + (indicatorsEnabled ? 26 : 0),
    );

    if (reader.mode == ReaderMode.scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_chapterController.hasClients) return;
        final page = _chapterController.page?.round();
        if (page != null && page != _index) {
          _chapterController.jumpToPage(_index);
        }
      });
    }

    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    _syncVolumeCapture(reader.volumeKeysTurnPages && routeCurrent);

    return PopScope(
      canPop: _chromeVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_chromeVisible) _toggleChrome();
      },
      child: Focus(
        focusNode: _readerFocus,
        autofocus: true,
        onKeyEvent: _handleReaderKey,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: skin.isDark ? appSystemOverlayStyle : _lightOverlayStyle,
          child: Scaffold(
            backgroundColor: skin.background,
            body: Stack(
              children: [
                Positioned.fill(
                  child: _memoizedContent(reader, contentPadding),
                ),
                if (indicatorsEnabled) _buildIndicators(reader, inset),
                if (_hasTranslation) _buildLanguageSwitch(reader, inset),
                _buildTopBar(reader, inset),
                _buildBottomBar(reader, inset),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleReaderKey(FocusNode node, KeyEvent event) {
    if (!_reader.volumeKeysTurnPages || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final direction = volumeKeyDirection(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    _onVolumeKey(direction);
    return KeyEventResult.handled;
  }

  void _onVolumeKey(int direction) {
    if (!mounted || !_reader.volumeKeysTurnPages) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final now = DateTime.now();
    final previous = _lastVolumeAt;
    // Collapse the native channel and the Flutter key event for the same
    // press. A different direction is always honored so up/down stay distinct.
    if (previous != null &&
        _lastVolumeDirection == direction &&
        now.difference(previous) < const Duration(milliseconds: 180)) {
      return;
    }
    _lastVolumeAt = now;
    _lastVolumeDirection = direction;
    _navigation.turn(direction);
  }

  void _syncVolumeCapture(bool enabled) {
    if (_volumeCapture == enabled) return;
    _volumeCapture = enabled;
    unawaited(ReaderSystem.setVolumeKeyCapture(enabled));
  }

  Future<void> _maybeShowBackgroundGuide({bool becauseFailed = false}) async {
    final settings = _settings;
    if (!mounted || settings == null) return;
    await BackgroundPlaybackGuide.maybeShow(
      context,
      dismissedForever: settings.backgroundPlaybackGuideDismissed,
      onDismissForever: settings.dismissBackgroundPlaybackGuide,
      becauseFailed: becauseFailed,
    );
  }

  /// Returns the same widget instance while nothing layout-relevant changed,
  /// so toggling the toolbar, ticking the clock or advancing the spoken
  /// sentence never rebuilds every paragraph of the chapter.
  Widget _memoizedContent(ReaderPreferences reader, EdgeInsets contentPadding) {
    final key = [
      _index,
      reader.layoutSignature,
      reader.mode.name,
      reader.paragraphSpacing,
      reader.showPageNumber,
      _showTranslation,
      _positionToken,
      contentPadding.toString(),
    ].join('#');
    final cached = _contentCache;
    if (cached != null && key == _contentCacheKey) return cached;
    _contentCacheKey = key;
    _contentCache = _buildContent(reader, contentPadding);
    return _contentCache!;
  }

  /// Sentence currently read aloud, but only while it belongs to this chapter.
  String? get _ttsHighlight {
    final tts = _tts;
    if (tts == null || !tts.isActive) return null;
    if (tts.book?.id != widget.book.id) return null;
    if (tts.chapterIndex != _index) return null;
    return tts.activeText;
  }

  Widget _buildContent(ReaderPreferences reader, EdgeInsets contentPadding) {
    if (_chapterCount == 0) {
      return Center(
        child: Text(
          '这本书没有可阅读的章节',
          style: TextStyle(color: reader.skin.secondary),
        ),
      );
    }

    if (reader.mode == ReaderMode.scroll) {
      return PageView.builder(
        controller: _chapterController,
        itemCount: _chapterCount,
        onPageChanged: _onSwipeChapter,
        itemBuilder: (context, index) {
          final chapter = widget.book.chapters[index];
          return ReaderScrollView(
            key: ValueKey(
              'scroll-${widget.book.id}-$index-'
              '${reader.layoutSignature}-${_showTranslation ? 1 : 0}-'
              '$_positionToken',
            ),
            chapterTitle: chapter.title,
            text: _textFor(index, chapter),
            isTranslation:
                _showTranslation &&
                widget.translation?.chapterFor(chapter.id) != null,
            reader: reader,
            contentPadding: contentPadding,
            initialFraction: index == _index ? _fraction.value : 0,
            onFractionChanged: (value) => _onFractionChanged(index, value),
            onToggleChrome: _toggleChrome,
            hasNextChapter: index < _chapterCount - 1,
            hasPreviousChapter: index > 0,
            navigation: index == _index ? _navigation : null,
            onPreviousChapter: () {
              if (index > 0) _goToChapter(index - 1, toStart: false);
            },
            onNextChapter: () {
              if (index < _chapterCount - 1) _goToChapter(index + 1);
            },
            highlight: index == _index ? _highlight : null,
          );
        },
      );
    }

    return ReaderPageView(
      key: ValueKey(
        'page-${widget.book.id}-$_index-'
        '${reader.layoutSignature}-${_showTranslation ? 1 : 0}-'
        '$_positionToken',
      ),
      chapterTitle: _chapter.title,
      text: _currentText,
      isTranslation:
          _showTranslation &&
          widget.translation?.chapterFor(_chapter.id) != null,
      reader: reader,
      contentPadding: contentPadding,
      initialFraction: _fraction.value,
      onFractionChanged: (value) => _onFractionChanged(_index, value),
      onToggleChrome: _toggleChrome,
      hasPreviousChapter: _index > 0,
      hasNextChapter: _index < _chapterCount - 1,
      selectable: _chromeVisible,
      highlight: _highlight,
      navigation: _navigation,
      onPreviousChapter: () {
        if (_index > 0) _goToChapter(_index - 1, toStart: false);
      },
      onNextChapter: () {
        if (_index < _chapterCount - 1) _goToChapter(_index + 1);
      },
    );
  }

  Widget _buildIndicators(ReaderPreferences reader, EdgeInsets inset) {
    final skin = reader.skin;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 16,
      right: 16,
      bottom: _chromeVisible
          ? inset.bottom + _kBottomBarHeight + 6
          : inset.bottom + 6,
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: _fraction,
          builder: (context, fraction, _) {
            final overall = _chapterCount == 0
                ? 0.0
                : ((_index + fraction) / _chapterCount).clamp(0.0, 1.0);
            return Row(
              children: [
                if (reader.showClock || reader.showProgress)
                  _IndicatorPill(
                    skin: skin,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (reader.showClock)
                          Text(
                            formatClockTime(_now),
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 0.6,
                              color: skin.secondary,
                            ),
                          ),
                        if (reader.showClock && reader.showProgress)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Text(
                              '·',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: skin.secondary,
                              ),
                            ),
                          ),
                        if (reader.showProgress)
                          Text(
                            '${(overall * 100).round()}%',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: skin.secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (reader.showChapterTitle)
                  Flexible(
                    child: _IndicatorPill(
                      skin: skin,
                      child: Text(
                        _chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 10.5, color: skin.secondary),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLanguageSwitch(ReaderPreferences reader, EdgeInsets inset) {
    final skin = reader.skin;
    final targetLabel = widget.translation?.target.label ?? '译文';
    return Positioned(
      right: 14,
      top: inset.top + _kTopBarHeight + 6,
      child: _AnimatedChrome(
        visible: _chromeVisible,
        fromTop: true,
        child: _LanguageSwitch(
          skin: skin,
          originalSelected: !_showTranslation,
          targetLabel: '译文 · $targetLabel',
          onChanged: (showTranslation) {
            if (showTranslation == _showTranslation) return;
            _toggleTranslation();
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(ReaderPreferences reader, EdgeInsets inset) {
    final skin = reader.skin;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: _AnimatedChrome(
        visible: _chromeVisible,
        fromTop: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: skin.chrome,
            border: Border(bottom: BorderSide(color: skin.line)),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: inset.top),
            child: SizedBox(
              height: _kTopBarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, color: skin.text),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: skin.secondary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.serif,
                            fontFamilyFallback: AppTheme.serifFallback,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: skin.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _fraction,
                    builder: (context, fraction, _) {
                      final marked =
                          _library?.bookmarkNear(
                            widget.book.id,
                            _index,
                            fraction,
                          ) !=
                          null;
                      return IconButton(
                        tooltip: marked ? '取消书签' : '添加书签',
                        onPressed: _toggleBookmark,
                        icon: Icon(
                          marked
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: marked ? skin.accent : skin.text,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '目录',
                    onPressed: _openChapters,
                    icon: Icon(Icons.list_rounded, color: skin.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderPreferences reader, EdgeInsets inset) {
    final skin = reader.skin;
    final ttsActive = _tts?.isReadingChapter(widget.book.id, _index) ?? false;
    final ttsButtonIcon = ttsActive
        ? Icons.graphic_eq_rounded
        : Icons.headphones_rounded;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _AnimatedChrome(
        visible: _chromeVisible,
        fromTop: false,
        child: Container(
          padding: EdgeInsets.only(bottom: inset.bottom),
          decoration: BoxDecoration(
            color: skin.chrome,
            border: Border(top: BorderSide(color: skin.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _kBottomBarHeight,
                child: Row(
                  children: [
                    _BarAction(
                      icon: Icons.menu_book_outlined,
                      label: '目录',
                      skin: skin,
                      onTap: _openChapters,
                    ),
                    _BarAction(
                      icon: Icons.arrow_back_rounded,
                      label: '上一章',
                      skin: skin,
                      onTap: _index > 0 ? () => _goToChapter(_index - 1) : null,
                    ),
                    Expanded(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _fraction,
                        builder: (context, fraction, _) {
                          final overall = _chapterCount == 0
                              ? 0.0
                              : ((_index + fraction) / _chapterCount).clamp(
                                  0.0,
                                  1.0,
                                );
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '第 ${_index + 1} / $_chapterCount 章',
                                style: TextStyle(
                                  fontFamily: AppTheme.serif,
                                  fontFamilyFallback: AppTheme.serifFallback,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: skin.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '全书 ${(overall * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: skin.secondary,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    _BarAction(
                      icon: Icons.arrow_forward_rounded,
                      label: '下一章',
                      skin: skin,
                      onTap: _index < _chapterCount - 1
                          ? () => _goToChapter(_index + 1)
                          : null,
                    ),
                    _BarAction(
                      icon: ttsButtonIcon,
                      label: '听书',
                      skin: skin,
                      onTap: _openTtsPlayer,
                    ),
                    _BarAction(
                      icon: Icons.tune_rounded,
                      label: '设置',
                      skin: skin,
                      onTap: _openReaderSettings,
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _fraction,
                builder: (context, fraction, _) {
                  final overall = _chapterCount == 0
                      ? 0.0
                      : ((_index + fraction) / _chapterCount).clamp(0.0, 1.0);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: overall,
                      minHeight: 2.5,
                      backgroundColor: skin.line,
                      valueColor: AlwaysStoppedAnimation<Color>(skin.accent),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _kTopBarHeight = 58;
const double _kBottomBarHeight = 82;

const SystemUiOverlayStyle _lightOverlayStyle = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.dark,
);

class _AnimatedChrome extends StatelessWidget {
  const _AnimatedChrome({
    required this.visible,
    required this.fromTop,
    required this.child,
  });

  final bool visible;
  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : Offset(0, fromTop ? -1 : 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      ),
    );
  }
}

class _IndicatorPill extends StatelessWidget {
  const _IndicatorPill({required this.skin, required this.child});

  final ReaderSkin skin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: skin.chrome.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: skin.line.withValues(alpha: 0.8)),
      ),
      child: child,
    );
  }
}

class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({
    required this.skin,
    required this.originalSelected,
    required this.targetLabel,
    required this.onChanged,
  });

  final ReaderSkin skin;
  final bool originalSelected;
  final String targetLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.background.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: skin.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill('原文', originalSelected, () => onChanged(false)),
          _pill(targetLabel, !originalSelected, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? skin.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? skin.background : skin.secondary,
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.skin,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final ReaderSkin skin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? skin.text : skin.secondary.withValues(alpha: 0.45);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10.5, color: color)),
          ],
        ),
      ),
    );
  }
}
