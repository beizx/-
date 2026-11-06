import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One fragment of a paragraph placed on a page. Offsets refer to the display
/// paragraph, which already includes the first-line indent.
class ReaderPageFragment {
  const ReaderPageFragment({
    required this.paragraphIndex,
    required this.start,
    required this.end,
  });

  final int paragraphIndex;
  final int start;
  final int end;

  String textOf(List<String> displayParagraphs) {
    final paragraph = displayParagraphs[paragraphIndex];
    final safeStart = start.clamp(0, paragraph.length);
    final safeEnd = end.clamp(safeStart, paragraph.length);
    return paragraph.substring(safeStart, safeEnd);
  }
}

/// A single rendered page made of paragraph fragments.
class ReaderPageContent {
  const ReaderPageContent({required this.fragments});

  final List<ReaderPageFragment> fragments;
}

class ReaderPagination {
  const ReaderPagination({
    required this.pages,
    required this.displayParagraphs,
  });

  static const empty = ReaderPagination(
    pages: <ReaderPageContent>[],
    displayParagraphs: <String>[],
  );

  final List<ReaderPageContent> pages;
  final List<String> displayParagraphs;

  bool get isEmpty => pages.isEmpty;
}

/// Splits novel text into paragraphs and lays them out into pages that match
/// the reader's typography. Pure Dart/Flutter text layout so the page count is
/// stable and testable.
abstract final class ReaderPaginator {
  static List<String> splitParagraphs(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final paragraphs = <String>[];
    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) paragraphs.add(trimmed);
    }
    return paragraphs;
  }

  static List<String> displayParagraphs(
    String text, {
    required double firstLineIndent,
  }) {
    final indent = '　' * firstLineIndent.round().clamp(0, 2);
    return [
      for (final paragraph in splitParagraphs(text))
        if (indent.isEmpty) paragraph else '$indent$paragraph',
    ];
  }

  static ReaderPagination paginate({
    required String text,
    required TextStyle textStyle,
    required double maxWidth,
    required double pageHeight,
    double? firstPageHeight,
    double paragraphSpacing = 0,
    double firstLineIndent = 0,
    TextAlign textAlign = TextAlign.start,
    TextScaler textScaler = TextScaler.noScaling,
    int maxPages = 2000,
  }) {
    final job = ReaderPaginationJob.start(
      text: text,
      textStyle: textStyle,
      maxWidth: maxWidth,
      pageHeight: pageHeight,
      firstPageHeight: firstPageHeight,
      paragraphSpacing: paragraphSpacing,
      firstLineIndent: firstLineIndent,
      textAlign: textAlign,
      textScaler: textScaler,
      maxPages: maxPages,
    );
    if (!job.isDone) {
      job.pump(paragraphBudget: math.max(job.paragraphCount, 1));
    }
    return job.snapshot();
  }

  static int _lineStartOffset(
    TextPainter painter,
    List<LineMetrics> metrics,
    int lineIndex,
    int textLength, {
    bool firstFragment = false,
  }) {
    if (lineIndex >= metrics.length) return textLength;
    if (lineIndex == 0 && firstFragment) return 0;
    final line = metrics[lineIndex];
    final y = line.baseline - line.ascent + line.height * 0.5;
    final position = painter.getPositionForOffset(Offset(0.5, y));
    return position.offset.clamp(0, textLength);
  }
}

/// How much text layout a single frame is allowed to do.
///
/// Long chapters are split across frames. Tests lower these limits to prove
/// a frame cannot lay out the whole chapter.
abstract final class ReaderLayoutBudget {
  static int syncParagraphLimit = 24;
  static int paragraphsPerFrame = 8;

  /// Chapters longer than this are split off the UI isolate before layout.
  static int isolateCharThreshold = 16000;

  static void reset() {
    syncParagraphLimit = 24;
    paragraphsPerFrame = 8;
    isolateCharThreshold = 16000;
  }
}

/// Incremental pagination. [pump] lays out at most a budget of paragraphs so
/// a long chapter does not block the UI isolate for a whole frame.
class ReaderPaginationJob {
  ReaderPaginationJob._({
    required this.paragraphs,
    required this.textStyle,
    required this.maxWidth,
    required this.pageHeight,
    required this.firstPageHeight,
    required this.paragraphSpacing,
    required this.textAlign,
    required this.textScaler,
    required this.maxPages,
    required this._done,
  });

  factory ReaderPaginationJob.start({
    required String text,
    required TextStyle textStyle,
    required double maxWidth,
    required double pageHeight,
    double? firstPageHeight,
    double paragraphSpacing = 0,
    double firstLineIndent = 0,
    TextAlign textAlign = TextAlign.start,
    TextScaler textScaler = TextScaler.noScaling,
    int maxPages = 2000,
  }) {
    final paragraphs = ReaderPaginator.displayParagraphs(
      text,
      firstLineIndent: firstLineIndent,
    );
    final safePageHeight = math.max(pageHeight, 24.0);
    final safeFirstHeight = math.max(
      math.min(firstPageHeight ?? safePageHeight, safePageHeight),
      24.0,
    );
    final empty = paragraphs.isEmpty || maxWidth <= 8 || pageHeight <= 8;
    final job = ReaderPaginationJob._(
      paragraphs: paragraphs,
      textStyle: textStyle,
      maxWidth: maxWidth,
      pageHeight: safePageHeight,
      firstPageHeight: safeFirstHeight,
      paragraphSpacing: paragraphSpacing.clamp(0.0, 48.0),
      textAlign: textAlign,
      textScaler: textScaler,
      maxPages: maxPages,
      done: empty,
    );
    job._remaining = safeFirstHeight;
    return job;
  }

  final List<String> paragraphs;
  final TextStyle textStyle;
  final double maxWidth;
  final double pageHeight;
  final double firstPageHeight;
  final double paragraphSpacing;
  final TextAlign textAlign;
  final TextScaler textScaler;
  final int maxPages;

  final List<ReaderPageContent> _pages = [];
  var _currentFragments = <ReaderPageFragment>[];
  var _remaining = 0.0;
  var _paragraphIndex = 0;
  var _done = false;

  /// Paragraphs actually laid out by the most recent [pump].
  int lastPumpLaidOut = 0;

  /// Visible to tests. A frame that paginates an entire long chapter sets
  /// this far above [ReaderLayoutBudget.paragraphsPerFrame].
  static int debugLastPumpLaidOut = 0;

  int get paragraphCount => paragraphs.length;
  int get paragraphsLaidOut => _paragraphIndex;
  bool get isDone => _done;

  bool pump({int paragraphBudget = 8}) {
    if (_done) {
      lastPumpLaidOut = 0;
      debugLastPumpLaidOut = 0;
      return true;
    }
    final before = _paragraphIndex;
    var budget = paragraphBudget < 0 ? 0 : paragraphBudget;
    while (_paragraphIndex < paragraphs.length &&
        budget > 0 &&
        _pages.length < maxPages) {
      _layoutParagraph(_paragraphIndex);
      _paragraphIndex++;
      budget--;
    }
    if (_paragraphIndex >= paragraphs.length || _pages.length >= maxPages) {
      _flush();
      _done = true;
    }
    lastPumpLaidOut = _paragraphIndex - before;
    debugLastPumpLaidOut = lastPumpLaidOut;
    return _done;
  }

  ReaderPagination snapshot() {
    if (paragraphs.isEmpty || maxWidth <= 8) return ReaderPagination.empty;
    final pages = List<ReaderPageContent>.of(_pages);
    if (_currentFragments.isNotEmpty) {
      pages.add(
        ReaderPageContent(fragments: List.unmodifiable(_currentFragments)),
      );
    }
    if (pages.isEmpty) return ReaderPagination.empty;
    return ReaderPagination(
      pages: List.unmodifiable(pages),
      displayParagraphs: List.unmodifiable(paragraphs),
    );
  }

  void _flush() {
    if (_currentFragments.isEmpty) return;
    _pages.add(
      ReaderPageContent(fragments: List.unmodifiable(_currentFragments)),
    );
    _currentFragments = <ReaderPageFragment>[];
    _remaining = pageHeight;
  }

  void _layoutParagraph(int paragraphIndex) {
    if (_pages.length >= maxPages) return;
    final paragraph = paragraphs[paragraphIndex];
    final painter = TextPainter(
      text: TextSpan(text: paragraph, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      textAlign: textAlign,
    )..layout(maxWidth: maxWidth);
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) {
      painter.dispose();
      return;
    }

    final minLineHeight = math.max(textStyle.fontSize ?? 16, 8) * 0.6;
    final gap = paragraphSpacing;
    if (_currentFragments.isNotEmpty) {
      _remaining -= gap;
      if (_remaining < math.max(minLineHeight, metrics.first.height * 0.8)) {
        _flush();
      }
    }

    var lineIndex = 0;
    var firstFragment = true;
    while (lineIndex < metrics.length) {
      if (_pages.length >= maxPages) break;
      if (_currentFragments.isNotEmpty &&
          _remaining <
              math.min(metrics[lineIndex].height * 0.8, minLineHeight)) {
        _flush();
      }

      final available = math.max(_remaining, metrics[lineIndex].height);
      final startLine = lineIndex;
      var used = 0.0;
      while (lineIndex < metrics.length &&
          used + metrics[lineIndex].height <= available + 0.5) {
        used += metrics[lineIndex].height;
        lineIndex++;
      }
      if (lineIndex == startLine) {
        used = metrics[lineIndex].height;
        lineIndex++;
      }

      var startOffset = ReaderPaginator._lineStartOffset(
        painter,
        metrics,
        startLine,
        paragraph.length,
        firstFragment: firstFragment,
      );
      while (startOffset < paragraph.length &&
          paragraph.codeUnitAt(startOffset) == 0x0A) {
        startOffset++;
      }
      var endOffset = lineIndex < metrics.length
          ? ReaderPaginator._lineStartOffset(
              painter,
              metrics,
              lineIndex,
              paragraph.length,
              firstFragment: false,
            )
          : paragraph.length;
      while (endOffset > startOffset &&
          paragraph.codeUnitAt(endOffset - 1) == 0x0A) {
        endOffset--;
      }
      if (endOffset <= startOffset) {
        endOffset = math.min(paragraph.length, startOffset + 1);
      }

      _currentFragments.add(
        ReaderPageFragment(
          paragraphIndex: paragraphIndex,
          start: startOffset,
          end: endOffset,
        ),
      );
      _remaining -= used;
      firstFragment = false;

      if (lineIndex < metrics.length) {
        _flush();
      }
    }
    painter.dispose();

    if (_currentFragments.isNotEmpty && _remaining < gap + minLineHeight) {
      _flush();
    }
  }
}
