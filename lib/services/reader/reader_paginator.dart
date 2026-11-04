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
    final paragraphs = displayParagraphs(
      text,
      firstLineIndent: firstLineIndent,
    );
    if (paragraphs.isEmpty || maxWidth <= 8 || pageHeight <= 8) {
      return ReaderPagination.empty;
    }

    final safePageHeight = math.max(pageHeight, 24.0);
    final safeFirstHeight = math.max(
      math.min(firstPageHeight ?? safePageHeight, safePageHeight),
      24.0,
    );
    final gap = paragraphSpacing.clamp(0.0, 48.0);

    final pages = <ReaderPageContent>[];
    var currentFragments = <ReaderPageFragment>[];
    var remaining = safeFirstHeight;
    final minLineHeight = math.max(textStyle.fontSize ?? 16, 8) * 0.6;

    void flush() {
      if (currentFragments.isEmpty) return;
      pages.add(
        ReaderPageContent(fragments: List.unmodifiable(currentFragments)),
      );
      currentFragments = <ReaderPageFragment>[];
      remaining = safePageHeight;
    }

    for (
      var paragraphIndex = 0;
      paragraphIndex < paragraphs.length;
      paragraphIndex++
    ) {
      if (pages.length >= maxPages) break;
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
        continue;
      }

      if (currentFragments.isNotEmpty) {
        remaining -= gap;
        if (remaining < math.max(minLineHeight, metrics.first.height * 0.8)) {
          flush();
        }
      }

      var lineIndex = 0;
      var firstFragment = true;
      while (lineIndex < metrics.length) {
        if (pages.length >= maxPages) break;
        if (currentFragments.isNotEmpty &&
            remaining <
                math.min(metrics[lineIndex].height * 0.8, minLineHeight)) {
          flush();
        }

        final available = math.max(remaining, metrics[lineIndex].height);
        final startLine = lineIndex;
        var used = 0.0;
        while (lineIndex < metrics.length &&
            used + metrics[lineIndex].height <= available + 0.5) {
          used += metrics[lineIndex].height;
          lineIndex++;
        }
        if (lineIndex == startLine) {
          // A single line does not fit on the current page; force it so a
          // pathological page height can never loop forever.
          used = metrics[lineIndex].height;
          lineIndex++;
        }

        var startOffset = _lineStartOffset(
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
            ? _lineStartOffset(
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

        currentFragments.add(
          ReaderPageFragment(
            paragraphIndex: paragraphIndex,
            start: startOffset,
            end: endOffset,
          ),
        );
        remaining -= used;
        firstFragment = false;

        if (lineIndex < metrics.length) {
          flush();
        }
      }
      painter.dispose();

      if (currentFragments.isNotEmpty && remaining < gap + minLineHeight) {
        flush();
      }
    }

    flush();
    return ReaderPagination(
      pages: List.unmodifiable(pages),
      displayParagraphs: List.unmodifiable(paragraphs),
    );
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
