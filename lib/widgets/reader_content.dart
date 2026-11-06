import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/text_utils.dart';
import '../models/reader_settings.dart';
import '../services/reader/reader_paginator.dart';
import '../services/reader/reader_scroll_layout.dart';

TextStyle readerBodyStyle(ReaderPreferences reader) {
  return TextStyle(
    fontFamily: reader.typeface.fontFamily,
    fontFamilyFallback: reader.typeface.fallback,
    fontSize: reader.fontSize,
    height: reader.lineHeight,
    fontWeight: reader.fontWeight.fontWeight,
    letterSpacing: 0.25,
    color: reader.skin.text,
  );
}

/// Lets the reader screen turn a page without rebuilding the chapter.
class ReaderNavigationHandle {
  void Function(int direction)? _turn;

  void turn(int direction) => _turn?.call(direction);

  void attach(void Function(int direction) turn) => _turn = turn;

  void detach(void Function(int direction) turn) {
    if (identical(_turn, turn)) _turn = null;
  }
}

/// Volume up moves backward, volume down moves forward.
int? volumeKeyDirection(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.audioVolumeUp) return -1;
  if (key == LogicalKeyboardKey.audioVolumeDown) return 1;
  return null;
}

/// Scroll positions are reported when the visible percent changes, at the
/// ends, on a short interval, or when the gesture ends. Pixel-by-pixel
/// callbacks are what made long chapters stutter.
bool shouldReportReadingFraction({
  required double? previous,
  required DateTime? previousAt,
  required double next,
  required DateTime now,
  bool force = false,
  Duration minInterval = const Duration(milliseconds: 250),
}) {
  if (force || previous == null) return true;
  if ((next - previous).abs() < 1e-9) return false;
  if (next <= 0.0005 || next >= 0.9995) return true;
  if ((previous * 100).round() != (next * 100).round()) return true;
  final at = previousAt;
  if (at == null) return true;
  return now.difference(at) >= minInterval;
}

/// Spoken sentence plus the paragraph that owns it.
///
/// Paragraph listeners are notified only for the paragraph that lost the
/// highlight and the one that gained it. The other paragraphs do no work.
class ReaderSpeechHighlight implements ValueListenable<String?> {
  final Set<VoidCallback> _global = <VoidCallback>{};
  final Map<int, Set<VoidCallback>> _byParagraph = <int, Set<VoidCallback>>{};
  String? _text;
  int? _paragraph;

  @override
  String? get value => _text;

  int? get paragraphIndex => _paragraph;

  @override
  void addListener(VoidCallback listener) => _global.add(listener);

  @override
  void removeListener(VoidCallback listener) => _global.remove(listener);

  void addParagraphListener(int index, VoidCallback listener) {
    (_byParagraph[index] ??= <VoidCallback>{}).add(listener);
  }

  void removeParagraphListener(int index, VoidCallback listener) {
    final set = _byParagraph[index];
    if (set == null) return;
    set.remove(listener);
    if (set.isEmpty) _byParagraph.remove(index);
  }

  void update({String? text, int? paragraphIndex}) {
    if (text == _text && paragraphIndex == _paragraph) return;
    final previous = _paragraph;
    _text = text;
    _paragraph = paragraphIndex;
    if (paragraphIndex == null) {
      if (previous != null) {
        _notifyParagraph(previous);
      } else {
        _notifyAllParagraphs();
      }
    } else if (previous == null) {
      _notifyParagraph(paragraphIndex);
    } else {
      _notifyParagraph(previous);
      if (previous != paragraphIndex) _notifyParagraph(paragraphIndex);
    }
    _notify(_global);
  }

  void dispose() {
    _global.clear();
    _byParagraph.clear();
  }

  void _notifyAllParagraphs() {
    final callbacks = <VoidCallback>[
      for (final set in _byParagraph.values) ...set,
    ];
    _notify(callbacks);
  }

  void _notifyParagraph(int index) {
    final set = _byParagraph[index];
    if (set == null || set.isEmpty) return;
    _notify(set);
  }

  void _notify(Iterable<VoidCallback> listeners) {
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }
}

TextStyle readerTitleStyle(ReaderPreferences reader) {
  return TextStyle(
    fontFamily: AppTheme.serif,
    fontFamilyFallback: AppTheme.serifFallback,
    fontSize: reader.fontSize + 7,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: reader.skin.text,
  );
}

/// Vertical scroll reader for one chapter. Taps toggle the chrome; scrolling
/// reports a 0..1 position so the parent can persist the exact spot.
class ReaderScrollView extends StatefulWidget {
  const ReaderScrollView({
    super.key,
    required this.chapterTitle,
    required this.text,
    required this.isTranslation,
    required this.reader,
    required this.contentPadding,
    required this.initialFraction,
    required this.onFractionChanged,
    required this.onToggleChrome,
    required this.hasNextChapter,
    this.hasPreviousChapter = false,
    this.onPreviousChapter,
    this.onNextChapter,
    this.navigation,
    this.highlight,
    this.prefetchText,
    this.prefetchTitle,
    this.prefetchTranslation = false,
    this.prefetchHasNext = false,
  });

  final String chapterTitle;
  final String text;
  final bool isTranslation;
  final ReaderPreferences reader;
  final EdgeInsets contentPadding;
  final double initialFraction;
  final ValueChanged<double> onFractionChanged;
  final VoidCallback onToggleChrome;
  final bool hasNextChapter;
  final bool hasPreviousChapter;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final ReaderNavigationHandle? navigation;

  /// Next chapter, measured while idle so a swipe does not lay it out inline.
  final String? prefetchText;
  final String? prefetchTitle;
  final bool prefetchTranslation;
  final bool prefetchHasNext;

  /// Utterance currently being read by the TTS engine.
  ///
  /// A listenable instead of a plain string: the reader no longer rebuilds the
  /// whole chapter when the spoken sentence advances.
  final ValueListenable<String?>? highlight;

  @override
  State<ReaderScrollView> createState() => _ReaderScrollViewState();
}

class _ReaderScrollViewState extends State<ReaderScrollView> {
  final ScrollController _controller = ScrollController();
  Offset? _downPosition;
  bool _restored = false;
  ReaderScrollLayout? _layout;
  String? _layoutKey;
  ReaderScrollLayoutJob? _job;
  String? _pendingKey;
  int _generation = 0;
  double _textWidth = 760;
  TextScaler _scaler = TextScaler.noScaling;
  TextStyle _ambient = const TextStyle();
  double? _lastReported;
  DateTime? _lastReportedAt;
  double? _pendingExact;
  String? _prefetchKey;
  int _prefetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    widget.navigation?.attach(_turnBy);
  }

  @override
  void didUpdateWidget(ReaderScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.navigation, widget.navigation)) {
      oldWidget.navigation?.detach(_turnBy);
      widget.navigation?.attach(_turnBy);
    }
  }

  void _turnBy(int direction) {
    final controller = _controller;
    if (!controller.hasClients) {
      _leaveChapter(direction);
      return;
    }
    final position = controller.position;
    final delta = position.viewportDimension * 0.92 * direction;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 12) {
      _leaveChapter(direction);
      return;
    }
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _leaveChapter(int direction) {
    if (direction < 0) {
      if (widget.hasPreviousChapter) widget.onPreviousChapter?.call();
    } else if (widget.hasNextChapter) {
      widget.onNextChapter?.call();
    }
  }

  void _restore() {
    if (!mounted || _restored || _layout == null) return;
    if (_controller.hasClients) {
      final max = _controller.position.maxScrollExtent;
      if (max > 0 && widget.initialFraction > 0.001) {
        _controller.jumpTo((widget.initialFraction * max).clamp(0.0, max));
      }
    }
    _restored = true;
  }

  double _readFraction() {
    if (!_controller.hasClients) return widget.initialFraction;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return 1;
    return (_controller.offset / max).clamp(0.0, 1.0);
  }

  void _emitFraction(double fraction, DateTime now) {
    _lastReported = fraction;
    _lastReportedAt = now;
    _pendingExact = null;
    widget.onFractionChanged(fraction);
  }

  void _handleScroll() {
    if (!_restored || !_controller.hasClients) return;
    final fraction = _readFraction();
    _pendingExact = fraction;
    final now = DateTime.now();
    if (!shouldReportReadingFraction(
      previous: _lastReported,
      previousAt: _lastReportedAt,
      next: fraction,
      now: now,
    )) {
      return;
    }
    _emitFraction(fraction, now);
  }

  bool _onScrollNotice(ScrollNotification notification) {
    if (notification is! ScrollEndNotification || !_restored) return false;
    final fraction = _pendingExact ?? _readFraction();
    if (_lastReported != null && (fraction - _lastReported!).abs() < 1e-9) {
      return false;
    }
    _emitFraction(fraction, DateTime.now());
    return false;
  }

  @override
  void dispose() {
    _generation++;
    _prefetchGeneration++;
    widget.navigation?.detach(_turnBy);
    _controller.dispose();
    super.dispose();
  }

  String _cacheKey({
    required String text,
    required String title,
    required bool translation,
    required bool hasNext,
    required ReaderPreferences reader,
    required TextAlign align,
  }) {
    final style = readerBodyStyle(reader);
    return [
      text.length,
      text.hashCode,
      title.length,
      title.hashCode,
      reader.firstLineIndent.toStringAsFixed(1),
      _textWidth.toStringAsFixed(1),
      style.fontSize?.toStringAsFixed(2),
      style.height?.toStringAsFixed(2),
      style.fontWeight?.value,
      style.fontFamily,
      style.letterSpacing?.toStringAsFixed(2),
      _scaler.scale(1).toStringAsFixed(3),
      _ambient.fontSize?.toStringAsFixed(2),
      _ambient.height?.toStringAsFixed(2),
      _ambient.fontFamily,
      align.name,
      reader.paragraphSpacing.toStringAsFixed(1),
      translation,
      hasNext,
    ].join('#');
  }

  void _ensureLayout(double textWidth, TextScaler scaler, TextAlign align) {
    _textWidth = textWidth;
    _scaler = scaler;
    final reader = widget.reader;
    final key = _cacheKey(
      text: widget.text,
      title: widget.chapterTitle,
      translation: widget.isTranslation,
      hasNext: widget.hasNextChapter,
      reader: reader,
      align: align,
    );
    if (_layout != null && _layoutKey == key) return;
    final cached = ReaderLayoutCache.scroll.get(key);
    if (cached != null) {
      _commitLayout(key, cached, duringBuild: true);
      return;
    }
    if (_pendingKey == key) return;
    _pendingKey = key;
    final generation = ++_generation;
    if (widget.text.length >= ReaderLayoutBudget.isolateCharThreshold) {
      unawaited(
        _prepareOffIsolate(
          generation,
          key,
          widget.text,
          reader.firstLineIndent,
          align,
        ),
      );
      return;
    }
    _beginJob(
      key,
      prepareReaderText(widget.text, reader.firstLineIndent),
      align,
      duringBuild: true,
      generation: generation,
    );
  }

  Future<void> _prepareOffIsolate(
    int generation,
    String key,
    String text,
    double indent,
    TextAlign align,
  ) async {
    PreparedReaderText prepared;
    try {
      prepared = await Isolate.run(() => prepareReaderText(text, indent));
    } catch (_) {
      prepared = prepareReaderText(text, indent);
    }
    if (!mounted || generation != _generation) return;
    _beginJob(key, prepared, align, duringBuild: false, generation: generation);
  }

  void _beginJob(
    String key,
    PreparedReaderText prepared,
    TextAlign align, {
    required bool duringBuild,
    required int generation,
  }) {
    if (!mounted || generation != _generation) return;
    final reader = widget.reader;
    final job = _jobFor(
      prepared: prepared,
      title: widget.chapterTitle,
      translation: widget.isTranslation,
      hasNext: widget.hasNextChapter,
      align: align,
      reader: reader,
    );
    if (prepared.paragraphs.length <= ReaderLayoutBudget.syncParagraphLimit) {
      if (!job.isDone) {
        // Chrome measurement consumes one unit of the budget.
        job.pump(paragraphBudget: prepared.paragraphs.length + 1);
      }
      _commitLayout(key, job.snapshot(), duringBuild: duringBuild);
      return;
    }
    _job = job;
    _pendingKey = key;
    _scheduleFrame(_pumpJob, generation);
  }

  ReaderScrollLayoutJob _jobFor({
    required PreparedReaderText prepared,
    required String title,
    required bool translation,
    required bool hasNext,
    required TextAlign align,
    required ReaderPreferences reader,
  }) {
    final label = translation
        ? '机器翻译 · 建议对照原文阅读'
        : '${formatCharacterCount(prepared.charCount)}字';
    return ReaderScrollLayoutJob(
      paragraphs: prepared.paragraphs,
      charCount: prepared.charCount,
      bodyStyle: readerBodyStyle(reader),
      titleStyle: readerTitleStyle(reader),
      metaStyle: TextStyle(fontSize: 10.5, color: reader.skin.secondary),
      textWidth: _textWidth,
      textAlign: align,
      textScaler: _scaler,
      paragraphSpacing: reader.paragraphSpacing,
      chapterTitle: title,
      metaLabel: label,
      hasNextChapter: hasNext,
      ambient: _ambient,
    );
  }

  void _pumpJob(int generation) {
    final job = _job;
    if (!mounted || job == null || generation != _generation) return;
    final done = job.pump(
      paragraphBudget: ReaderLayoutBudget.paragraphsPerFrame,
    );
    if (!done) {
      _scheduleFrame(_pumpJob, generation);
      return;
    }
    _commitLayout(_pendingKey ?? '', job.snapshot(), duringBuild: false);
  }

  void _commitLayout(
    String key,
    ReaderScrollLayout layout, {
    required bool duringBuild,
  }) {
    _layout = layout;
    _layoutKey = key;
    _job = null;
    _restored = false;
    ReaderLayoutCache.scroll.put(key, layout);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    _schedulePrefetch();
    if (!duringBuild && mounted) setState(() {});
  }

  void _schedulePrefetch() {
    final text = widget.prefetchText;
    if (text == null || _layout == null) return;
    final reader = widget.reader;
    final align = reader.justify ? TextAlign.justify : TextAlign.start;
    final key = _cacheKey(
      text: text,
      title: widget.prefetchTitle ?? '',
      translation: widget.prefetchTranslation,
      hasNext: widget.prefetchHasNext,
      reader: reader,
      align: align,
    );
    if (ReaderLayoutCache.scroll.get(key) != null || _prefetchKey == key) {
      return;
    }
    _prefetchKey = key;
    final generation = ++_prefetchGeneration;
    final prepared = prepareReaderText(text, reader.firstLineIndent);
    final job = _jobFor(
      prepared: prepared,
      title: widget.prefetchTitle ?? '',
      translation: widget.prefetchTranslation,
      hasNext: widget.prefetchHasNext,
      align: align,
      reader: reader,
    );
    _stepPrefetch(generation, key, job);
  }

  void _scheduleFrame(void Function(int generation) step, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) => step(generation));
    WidgetsBinding.instance.scheduleFrame();
  }

  void _stepPrefetch(int generation, String key, ReaderScrollLayoutJob job) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _prefetchGeneration) return;
      if (ReaderLayoutCache.scroll.get(key) != null) return;
      final done = job.pump(
        paragraphBudget: ReaderLayoutBudget.paragraphsPerFrame,
      );
      if (!done) {
        _stepPrefetch(generation, key, job);
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      ReaderLayoutCache.scroll.put(key, job.snapshot());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    final align = reader.justify ? TextAlign.justify : TextAlign.start;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 760.0;
        final textWidth = math.min(
          760.0,
          math.max(viewport - widget.contentPadding.horizontal, 40.0),
        );
        final scaler = MediaQuery.textScalerOf(context);
        _ambient = DefaultTextStyle.of(context).style;
        _ensureLayout(textWidth, scaler, align);
        final layout = _layout;
        if (layout == null || _layoutKey == null) {
          return Padding(
            padding: widget.contentPadding,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: textWidth,
                child: Text(
                  widget.chapterTitle,
                  style: readerTitleStyle(reader),
                ),
              ),
            ),
          );
        }
        return _buildList(reader, layout, align);
      },
    );
  }

  Widget _buildList(
    ReaderPreferences reader,
    ReaderScrollLayout layout,
    TextAlign align,
  ) {
    final skin = reader.skin;
    final bodyStyle = readerBodyStyle(reader);
    final highlightColor = skin.accent.withValues(alpha: 0.28);
    return Listener(
      onPointerDown: (event) => _downPosition = event.position,
      onPointerUp: (event) {
        final start = _downPosition;
        _downPosition = null;
        if (start == null) return;
        if ((event.position - start).distance > 12) return;
        widget.onToggleChrome();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotice,
        child: ListView.builder(
          controller: _controller,
          padding: widget.contentPadding,
          itemCount: layout.itemCount,
          scrollCacheExtent: const ScrollCacheExtent.pixels(360),
          addAutomaticKeepAlives: false,
          itemExtentBuilder: (index, dimensions) => layout.extentOf(index),
          itemBuilder: (context, index) {
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: layout.textWidth,
                child: _item(
                  index,
                  layout,
                  reader,
                  skin,
                  bodyStyle,
                  align,
                  highlightColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _item(
    int index,
    ReaderScrollLayout layout,
    ReaderPreferences reader,
    ReaderSkin skin,
    TextStyle bodyStyle,
    TextAlign align,
    Color highlightColor,
  ) {
    if (index == 0) return _header(reader, skin, layout);
    if (layout.paragraphs.isEmpty) {
      if (index == 1) return _empty(skin, layout);
      return _footer(skin, layout);
    }
    if (index == layout.paragraphs.length + 1) return _footer(skin, layout);
    final paragraphIndex = index - 1;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.paragraphSpacing),
      child: SelectionArea(
        child: ReaderHighlightedParagraph(
          text: layout.paragraphs[paragraphIndex],
          paragraphIndex: paragraphIndex,
          style: bodyStyle,
          align: align,
          highlight: widget.highlight,
          highlightColor: highlightColor,
          highlightTextColor: skin.text,
        ),
      ),
    );
  }

  Widget _header(
    ReaderPreferences reader,
    ReaderSkin skin,
    ReaderScrollLayout layout,
  ) {
    final label = widget.isTranslation
        ? '机器翻译 · 建议对照原文阅读'
        : '${formatCharacterCount(layout.charCount)}字';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.chapterTitle, style: readerTitleStyle(reader)),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 32,
              height: 2,
              color: skin.accent.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: skin.secondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _empty(ReaderSkin skin, ReaderScrollLayout layout) {
    return SizedBox(
      height: layout.emptyHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            widget.isTranslation ? '这一章暂时没有译文' : '这一章没有正文',
            style: TextStyle(fontSize: 13, color: skin.secondary),
          ),
        ),
      ),
    );
  }

  Widget _footer(ReaderSkin skin, ReaderScrollLayout layout) {
    return SizedBox(
      height: layout.footerHeight,
      child: Column(
        children: [
          const SizedBox(height: 26),
          Center(
            child: Column(
              children: [
                Container(width: 36, height: 1, color: skin.line),
                const SizedBox(height: 10),
                Text(
                  '本章完',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 3,
                    color: skin.secondary,
                  ),
                ),
                if (widget.hasNextChapter) ...[
                  const SizedBox(height: 4),
                  Text(
                    '左右滑动进入下一章',
                    style: TextStyle(
                      fontSize: 10,
                      color: skin.secondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders one paragraph, optionally highlighting the sentence being read.
///
/// The highlight is a plain substring match: TTS utterances are whole
/// paragraphs or punctuation-bounded slices of one, so a match is the common
/// case and the fallback (no highlight) is invisible to the reader.
Widget readerParagraphText(
  String paragraph, {
  required TextStyle style,
  required TextAlign align,
  String? highlightText,
  Color? highlightColor,
  Color? highlightTextColor,
}) {
  final needle = highlightText?.trim() ?? '';
  if (needle.isEmpty) {
    return Text(paragraph, style: style, textAlign: align);
  }
  final index = paragraph.indexOf(needle);
  if (index < 0) {
    return Text(paragraph, style: style, textAlign: align);
  }
  return Text.rich(
    TextSpan(
      children: [
        if (index > 0) TextSpan(text: paragraph.substring(0, index)),
        TextSpan(
          text: needle,
          style: TextStyle(
            color: highlightTextColor,
            backgroundColor: highlightColor,
          ),
        ),
        if (index + needle.length < paragraph.length)
          TextSpan(text: paragraph.substring(index + needle.length)),
      ],
    ),
    style: style,
    textAlign: align,
  );
}

/// One paragraph that only re-lays itself out when the spoken sentence moves
/// into it.
///
/// The plain [Text] is built once and handed to the [ValueListenableBuilder] as
/// `child`. When the highlight does not belong to this paragraph the very same
/// widget instance is returned, and Flutter skips the rebuild — so 听书 costs
/// one paragraph per sentence instead of the whole chapter.
class ReaderHighlightedParagraph extends StatelessWidget {
  const ReaderHighlightedParagraph({
    super.key,
    required this.text,
    required this.style,
    required this.align,
    required this.highlight,
    this.paragraphIndex,
    this.highlightColor,
    this.highlightTextColor,
  });

  final String text;
  final TextStyle style;
  final TextAlign align;
  final ValueListenable<String?>? highlight;

  /// When set together with a [ReaderSpeechHighlight], only this paragraph is
  /// told about a sentence that belongs to it.
  final int? paragraphIndex;
  final Color? highlightColor;
  final Color? highlightTextColor;

  @override
  Widget build(BuildContext context) {
    final plain = Text(text, style: style, textAlign: align);
    final listenable = highlight;
    if (listenable == null) return plain;
    final index = paragraphIndex;
    if (listenable is ReaderSpeechHighlight && index != null) {
      return _ScopedParagraphHighlight(
        bus: listenable,
        paragraphIndex: index,
        text: text,
        style: style,
        align: align,
        plain: plain,
        highlightColor: highlightColor,
        highlightTextColor: highlightTextColor,
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: listenable,
      child: plain,
      builder: (context, value, child) {
        final needle = value?.trim() ?? '';
        if (needle.isEmpty || !text.contains(needle)) return child!;
        return readerParagraphText(
          text,
          style: style,
          align: align,
          highlightText: needle,
          highlightColor: highlightColor,
          highlightTextColor: highlightTextColor,
        );
      },
    );
  }
}

class _ScopedParagraphHighlight extends StatefulWidget {
  const _ScopedParagraphHighlight({
    required this.bus,
    required this.paragraphIndex,
    required this.text,
    required this.style,
    required this.align,
    required this.plain,
    this.highlightColor,
    this.highlightTextColor,
  });

  final ReaderSpeechHighlight bus;
  final int paragraphIndex;
  final String text;
  final TextStyle style;
  final TextAlign align;
  final Widget plain;
  final Color? highlightColor;
  final Color? highlightTextColor;

  @override
  State<_ScopedParagraphHighlight> createState() =>
      _ScopedParagraphHighlightState();
}

class _ScopedParagraphHighlightState extends State<_ScopedParagraphHighlight> {
  @override
  void initState() {
    super.initState();
    widget.bus.addParagraphListener(widget.paragraphIndex, _onHighlight);
  }

  @override
  void didUpdateWidget(_ScopedParagraphHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bus, widget.bus) ||
        oldWidget.paragraphIndex != widget.paragraphIndex) {
      oldWidget.bus.removeParagraphListener(
        oldWidget.paragraphIndex,
        _onHighlight,
      );
      widget.bus.addParagraphListener(widget.paragraphIndex, _onHighlight);
    }
  }

  @override
  void dispose() {
    widget.bus.removeParagraphListener(widget.paragraphIndex, _onHighlight);
    super.dispose();
  }

  void _onHighlight() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final needle = widget.bus.value?.trim() ?? '';
    final active = widget.bus.paragraphIndex == widget.paragraphIndex;
    if (!active || needle.isEmpty || !widget.text.contains(needle)) {
      return widget.plain;
    }
    return readerParagraphText(
      widget.text,
      style: widget.style,
      align: widget.align,
      highlightText: needle,
      highlightColor: widget.highlightColor,
      highlightTextColor: widget.highlightTextColor,
    );
  }
}

/// Paginated reader for one chapter. A leading and trailing sentinel page let
/// the reader swipe into the adjacent chapters naturally.
class ReaderPageView extends StatefulWidget {
  const ReaderPageView({
    super.key,
    required this.chapterTitle,
    required this.text,
    required this.isTranslation,
    required this.reader,
    required this.contentPadding,
    required this.initialFraction,
    required this.onFractionChanged,
    required this.onToggleChrome,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
    required this.onPreviousChapter,
    required this.onNextChapter,
    this.selectable = false,
    this.navigation,
    this.highlight,
    this.prefetchText,
    this.prefetchTitle,
  });

  final String chapterTitle;
  final String text;
  final bool isTranslation;
  final ReaderPreferences reader;
  final EdgeInsets contentPadding;
  final double initialFraction;
  final ValueChanged<double> onFractionChanged;
  final VoidCallback onToggleChrome;
  final bool hasPreviousChapter;
  final bool hasNextChapter;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;
  final ReaderNavigationHandle? navigation;

  /// Text selection is enabled while the toolbar is visible. The default
  /// immersive state keeps horizontal drags free for page turning.
  final bool selectable;

  /// Sentence being read aloud, highlighted in place.
  final ValueListenable<String?>? highlight;

  /// Laid out while idle so turning into the next chapter does not paginate
  /// it on the gesture frame.
  final String? prefetchText;
  final String? prefetchTitle;

  @override
  State<ReaderPageView> createState() => _ReaderPageViewState();
}

class _ReaderPageViewState extends State<ReaderPageView> {
  ReaderPagination _pagination = ReaderPagination.empty;
  String _layoutKey = '';
  PageController? _controller;
  int _currentPage = 0;
  double _currentFraction = 0;
  bool _switchingChapter = false;

  /// `text.runes.length` is O(n); the header shows it on every build.
  int _charCount = 0;
  String _charCountKey = '';

  /// Title height only depends on the title, typography, width and text scale,
  /// so the TextPainter run is cached instead of repeated on every build.
  double _titleHeight = 0;
  String _titleHeightKey = '';
  ReaderPaginationJob? _job;
  String? _jobKey;
  bool _paging = false;
  String? _prefetchKey;
  int _prefetchGeneration = 0;
  Size _layoutSize = Size.zero;
  double _contentWidth = 0;
  double _bodyHeight = 0;
  TextAlign _layoutAlign = TextAlign.start;
  TextScaler _layoutScaler = TextScaler.noScaling;

  @override
  void initState() {
    super.initState();
    _currentFraction = widget.initialFraction.clamp(0.0, 1.0);
    widget.navigation?.attach(_turnPage);
  }

  @override
  void didUpdateWidget(ReaderPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.navigation, widget.navigation)) {
      oldWidget.navigation?.detach(_turnPage);
      widget.navigation?.attach(_turnPage);
    }
  }

  @override
  void dispose() {
    _prefetchGeneration++;
    widget.navigation?.detach(_turnPage);
    _controller?.dispose();
    super.dispose();
  }

  int _pageForFraction(int count, double fraction) {
    if (count <= 0) return 0;
    if (fraction >= 0.999) return count - 1;
    if (fraction <= 0.001) return 0;
    return ((fraction * count).ceil() - 1).clamp(0, count - 1);
  }

  double _fractionForPage(int page, int count) {
    if (count <= 0) return 0;
    return ((page + 1) / count).clamp(0.0, 1.0);
  }

  String _paginationKey({
    required String text,
    required String title,
    required Size size,
    required TextAlign align,
    required TextScaler textScaler,
    required ReaderPreferences reader,
  }) {
    return [
      text.length,
      text.hashCode,
      title,
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      reader.layoutSignature,
      reader.paragraphSpacing.toStringAsFixed(1),
      reader.showPageNumber,
      align.name,
      textScaler.scale(1).toStringAsFixed(3),
      widget.contentPadding.left.toStringAsFixed(1),
      widget.contentPadding.top.toStringAsFixed(1),
      widget.contentPadding.right.toStringAsFixed(1),
      widget.contentPadding.bottom.toStringAsFixed(1),
    ].join('#');
  }

  void _ensureLayout(
    ReaderPreferences reader,
    Size size,
    TextAlign align,
    double titleHeight,
    double bodyHeight,
    TextScaler textScaler,
  ) {
    _layoutSize = size;
    _layoutAlign = align;
    _layoutScaler = textScaler;
    _bodyHeight = bodyHeight;
    _contentWidth = size.width - widget.contentPadding.horizontal;
    final key = _paginationKey(
      text: widget.text,
      title: widget.chapterTitle,
      size: size,
      align: align,
      textScaler: textScaler,
      reader: reader,
    );

    if (key == _layoutKey && _job == null) return;
    final cached = ReaderLayoutCache.pagination.get(key);
    if (cached != null) {
      _installPagination(cached, key);
      _schedulePagePrefetch();
      return;
    }
    if (_job != null && _jobKey == key) return;

    final firstBodyHeight = titleHeight <= 0
        ? bodyHeight
        : math.max(bodyHeight - titleHeight - 42, 40.0);
    final job = ReaderPaginationJob.start(
      text: widget.text,
      textStyle: readerBodyStyle(reader),
      maxWidth: math.max(_contentWidth, 40.0),
      pageHeight: math.max(bodyHeight, 40.0),
      firstPageHeight: firstBodyHeight,
      paragraphSpacing: reader.paragraphSpacing,
      firstLineIndent: reader.firstLineIndent,
      textAlign: align,
      textScaler: textScaler,
    );
    if (job.isDone ||
        job.paragraphCount <= ReaderLayoutBudget.syncParagraphLimit) {
      if (!job.isDone) {
        job.pump(paragraphBudget: math.max(job.paragraphCount, 1));
      }
      final result = job.snapshot();
      ReaderLayoutCache.pagination.put(key, result);
      _installPagination(result, key);
      _schedulePagePrefetch();
      return;
    }
    _job = job;
    _jobKey = key;
    _paging = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpPagination());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _installPagination(ReaderPagination pagination, String key) {
    final hadLayout = _layoutKey.isNotEmpty;
    final fraction = hadLayout
        ? _currentFraction
        : widget.initialFraction.clamp(0.0, 1.0);
    _pagination = pagination;
    _layoutKey = key;
    _job = null;
    _paging = false;
    final count = _pagination.pages.length;
    _currentPage = _pageForFraction(count, fraction);
    _currentFraction = count <= 0 ? 0 : _fractionForPage(_currentPage, count);
    if (hadLayout) {
      widget.onFractionChanged(_currentFraction);
    }

    final previousController = _controller;
    _controller = PageController(initialPage: _currentPage + 1);
    if (previousController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }
  }

  void _pumpPagination() {
    final job = _job;
    if (!mounted || job == null) return;
    final done = job.pump(
      paragraphBudget: ReaderLayoutBudget.paragraphsPerFrame,
    );
    if (!done) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pumpPagination());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    final key = _jobKey ?? '';
    final result = job.snapshot();
    ReaderLayoutCache.pagination.put(key, result);
    setState(() => _installPagination(result, key));
    _schedulePagePrefetch();
  }

  void _schedulePagePrefetch() {
    final text = widget.prefetchText;
    final title = widget.prefetchTitle;
    if (text == null || title == null || _contentWidth <= 0) return;
    final reader = widget.reader;
    final key = _paginationKey(
      text: text,
      title: title,
      size: _layoutSize,
      align: _layoutAlign,
      textScaler: _layoutScaler,
      reader: reader,
    );
    if (ReaderLayoutCache.pagination.get(key) != null || _prefetchKey == key) {
      return;
    }
    _prefetchKey = key;
    final generation = ++_prefetchGeneration;
    final titleHeight = _measureTitleHeight(
      math.max(_contentWidth, 40),
      readerTitleStyle(reader),
      _layoutScaler,
      title: title,
    );
    final firstBodyHeight = titleHeight <= 0
        ? _bodyHeight
        : math.max(_bodyHeight - titleHeight - 42, 40.0);
    final job = ReaderPaginationJob.start(
      text: text,
      textStyle: readerBodyStyle(reader),
      maxWidth: math.max(_contentWidth, 40.0),
      pageHeight: math.max(_bodyHeight, 40.0),
      firstPageHeight: firstBodyHeight,
      paragraphSpacing: reader.paragraphSpacing,
      firstLineIndent: reader.firstLineIndent,
      textAlign: _layoutAlign,
      textScaler: _layoutScaler,
    );
    _stepPagePrefetch(generation, key, job);
  }

  void _stepPagePrefetch(int generation, String key, ReaderPaginationJob job) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _prefetchGeneration) return;
      if (ReaderLayoutCache.pagination.get(key) != null) return;
      final done =
          job.isDone ||
          job.pump(paragraphBudget: ReaderLayoutBudget.paragraphsPerFrame);
      if (!done) {
        _stepPagePrefetch(generation, key, job);
        return;
      }
      ReaderLayoutCache.pagination.put(key, job.snapshot());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _requestChapter(int direction) {
    if (_switchingChapter) return;
    if (direction < 0) {
      if (widget.hasPreviousChapter) {
        _switchingChapter = true;
        widget.onPreviousChapter();
      } else {
        _showEdgeHint('已经是第一页了');
        _snapBackToFirstPage();
      }
    } else {
      if (widget.hasNextChapter) {
        _switchingChapter = true;
        widget.onNextChapter();
      } else {
        _showEdgeHint('已经是最后一页了');
        _snapBackToLastPage();
      }
    }
  }

  void _showEdgeHint(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  void _snapBackToFirstPage() {
    if (_controller?.hasClients ?? false) {
      _controller!.animateToPage(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _snapBackToLastPage() {
    final count = _pagination.pages.length;
    if (count > 0 && (_controller?.hasClients ?? false)) {
      _controller!.animateToPage(
        count,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _turnPage(int direction) {
    final count = _pagination.pages.length;
    if (count == 0 || _controller == null) return;
    final targetPage = _currentPage + direction;
    if (targetPage < 0) {
      _requestChapter(-1);
      return;
    }
    if (targetPage >= count) {
      _requestChapter(1);
      return;
    }
    final target = targetPage + 1;
    if (widget.reader.turnAnimation == ReaderTurnAnimation.none) {
      _controller!.jumpToPage(target);
    } else {
      _controller!.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleTap(Offset position, Size size) {
    if (!widget.reader.tapToTurnPage) {
      widget.onToggleChrome();
      return;
    }
    if (position.dx < size.width * 0.28) {
      _turnPage(-1);
    } else if (position.dx > size.width * 0.72) {
      _turnPage(1);
    } else {
      widget.onToggleChrome();
    }
  }

  void _handlePageChanged(int index) {
    final count = _pagination.pages.length;
    if (index == 0) {
      _requestChapter(-1);
      return;
    }
    if (index == count + 1) {
      _requestChapter(1);
      return;
    }
    final realPage = (index - 1).clamp(0, math.max(count - 1, 0)).toInt();
    if (realPage == _currentPage) return;
    _currentPage = realPage;
    _currentFraction = _fractionForPage(realPage, count);
    widget.onFractionChanged(_currentFraction);
  }

  double _measureTitleHeight(
    double maxWidth,
    TextStyle style,
    TextScaler textScaler, {
    String? title,
  }) {
    final measuredTitle = title ?? widget.chapterTitle;
    if (measuredTitle.trim().isEmpty) return 0;
    final key = [
      measuredTitle,
      maxWidth.toStringAsFixed(1),
      style.fontSize?.toStringAsFixed(1) ?? '',
      style.height?.toStringAsFixed(2) ?? '',
      style.fontWeight?.value ?? 0,
      style.fontFamily ?? '',
      textScaler.scale(1).toStringAsFixed(3),
    ].join('#');
    if (key == _titleHeightKey) return _titleHeight;

    final painter = TextPainter(
      text: TextSpan(text: measuredTitle, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    _titleHeight = painter.height;
    _titleHeightKey = key;
    painter.dispose();
    return _titleHeight;
  }

  int _charCountFor(String text) {
    if (!identical(_charCountKey, text)) {
      _charCountKey = text;
      _charCount = text.runes.length;
    }
    return _charCount;
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    final skin = reader.skin;

    return LayoutBuilder(
      builder: (context, constraints) {
        final align = reader.justify ? TextAlign.justify : TextAlign.start;
        final textScaler = MediaQuery.textScalerOf(context);
        final titleHeight = _measureTitleHeight(
          math.max(constraints.maxWidth - widget.contentPadding.horizontal, 40),
          readerTitleStyle(reader),
          textScaler,
        );
        final bodyHeight =
            constraints.maxHeight -
            widget.contentPadding.vertical -
            (reader.showPageNumber ? 22 : 0);
        _ensureLayout(
          reader,
          constraints.biggest,
          align,
          titleHeight,
          bodyHeight,
          textScaler,
        );

        final pages = _pagination.pages;
        final controller = _controller;
        if (pages.isEmpty || controller == null) {
          if (_paging || _job != null) {
            return Padding(
              padding: widget.contentPadding,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  widget.chapterTitle,
                  style: readerTitleStyle(reader),
                ),
              ),
            );
          }
          return Center(
            child: Text(
              widget.isTranslation ? '这一章暂时没有译文' : '这一章没有正文',
              style: TextStyle(color: skin.secondary),
            ),
          );
        }

        return PageView.builder(
          key: ValueKey(_layoutKey),
          controller: controller,
          onPageChanged: _handlePageChanged,
          itemCount: pages.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _ChapterEdgePage(
                skin: skin,
                title: '已经是第一页了',
                subtitle: widget.hasPreviousChapter ? '向右滑动返回上一章' : '这里是故事的开头',
                enabled: widget.hasPreviousChapter,
                onTap: () => _requestChapter(-1),
              );
            }
            if (index == pages.length + 1) {
              return _ChapterEdgePage(
                skin: skin,
                title: '已经是最后一页了',
                subtitle: widget.hasNextChapter ? '向左滑动进入下一章' : '故事到这里结束',
                enabled: widget.hasNextChapter,
                onTap: () => _requestChapter(1),
              );
            }
            return _buildPageContent(
              context,
              index - 1,
              constraints.biggest,
              titleHeight,
            );
          },
        );
      },
    );
  }

  Widget _buildPageContent(
    BuildContext context,
    int pageIndex,
    Size size,
    double titleHeight,
  ) {
    final reader = widget.reader;
    final skin = reader.skin;
    final page = _pagination.pages[pageIndex];
    final isFirst = pageIndex == 0;
    final bodyStyle = readerBodyStyle(reader);
    final align = reader.justify ? TextAlign.justify : TextAlign.start;

    Widget? header;
    if (isFirst) {
      header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.chapterTitle, style: readerTitleStyle(reader)),
          const SizedBox(height: 10),
          SizedBox(
            height: 14,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 2,
                  color: skin.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isTranslation
                      ? '机器翻译 · 建议对照原文阅读'
                      : '${formatCharacterCount(_charCountFor(widget.text))}字',
                  style: TextStyle(fontSize: 10.5, color: skin.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    }

    final fragments = <Widget>[];
    for (var i = 0; i < page.fragments.length; i++) {
      final fragment = page.fragments[i];
      if (i > 0 &&
          fragment.paragraphIndex != page.fragments[i - 1].paragraphIndex) {
        fragments.add(SizedBox(height: reader.paragraphSpacing));
      }
      fragments.add(
        ReaderHighlightedParagraph(
          text: fragment.textOf(_pagination.displayParagraphs),
          paragraphIndex: fragment.paragraphIndex,
          style: bodyStyle,
          align: align,
          highlight: widget.highlight,
          highlightColor: skin.accent.withValues(alpha: 0.28),
          highlightTextColor: skin.text,
        ),
      );
    }
    final contentWidth = size.width - widget.contentPadding.horizontal;
    final pageBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [?header, ...fragments],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _handleTap(details.localPosition, size),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: widget.contentPadding,
              // A plain clipped column keeps horizontal drags available to the
              // surrounding PageView; a nested scroll view would swallow them.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  maxWidth: contentWidth,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: SizedBox(
                    width: contentWidth,
                    child: RepaintBoundary(
                      child: widget.selectable
                          ? SelectionArea(child: pageBody)
                          : pageBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (reader.showPageNumber)
            Positioned(
              left: widget.contentPadding.left,
              right: widget.contentPadding.right,
              bottom: math.max(
                widget.contentPadding.bottom - 22,
                MediaQuery.paddingOf(context).bottom + 30,
              ),
              child: Center(
                child: Text(
                  '第 ${pageIndex + 1} / ${_pagination.pages.length} 页',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: skin.secondary.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterEdgePage extends StatelessWidget {
  const _ChapterEdgePage({
    required this.skin,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final ReaderSkin skin;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 30,
                color: skin.secondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppTheme.serif,
                  fontFamilyFallback: AppTheme.serifFallback,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: skin.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: skin.secondary),
              ),
              if (enabled) ...[
                const SizedBox(height: 16),
                Icon(
                  Icons.keyboard_double_arrow_right_rounded,
                  size: 19,
                  color: skin.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
