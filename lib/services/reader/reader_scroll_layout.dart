import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'reader_paginator.dart';

/// Paragraphs plus the heights the scroll view uses as item extents.
///
/// Extents are known up front, so the scroll fraction stays `offset / max`
/// without laying out off-screen paragraphs.
class ReaderScrollLayout {
  const ReaderScrollLayout({
    required this.paragraphs,
    required this.paragraphHeights,
    required this.headerHeight,
    required this.footerHeight,
    required this.emptyHeight,
    required this.charCount,
    required this.paragraphSpacing,
    required this.textWidth,
  });

  final List<String> paragraphs;
  final List<double> paragraphHeights;
  final double headerHeight;
  final double footerHeight;
  final double emptyHeight;
  final int charCount;
  final double paragraphSpacing;
  final double textWidth;

  int get itemCount => paragraphs.isEmpty ? 3 : paragraphs.length + 2;

  double extentOf(int index) {
    if (index <= 0) return headerHeight;
    if (paragraphs.isEmpty) {
      return index == 1 ? emptyHeight : footerHeight;
    }
    if (index >= paragraphs.length + 1) return footerHeight;
    return paragraphHeights[index - 1] + paragraphSpacing;
  }
}

/// One frame of scroll measurement. The result matches a full measurement.
class ReaderScrollLayoutJob {
  ReaderScrollLayoutJob({
    required this.paragraphs,
    required this.charCount,
    required this.bodyStyle,
    required this.titleStyle,
    required this.metaStyle,
    required this.textWidth,
    required this.textAlign,
    required this.textScaler,
    required this.paragraphSpacing,
    required this.chapterTitle,
    required this.metaLabel,
    required this.hasNextChapter,
    required this.ambient,
  });

  final List<String> paragraphs;
  final int charCount;
  final TextStyle bodyStyle;
  final TextStyle titleStyle;
  final TextStyle metaStyle;
  final double textWidth;
  final TextAlign textAlign;
  final TextScaler textScaler;
  final double paragraphSpacing;
  final String chapterTitle;
  final String metaLabel;
  final bool hasNextChapter;

  /// Ambient [DefaultTextStyle]. Text widgets inherit it; the measurer must too.
  final TextStyle ambient;

  TextStyle _paint(TextStyle style) => ambient.merge(style);

  final List<double> _heights = [];
  var _chromeReady = false;
  var _headerHeight = 0.0;
  var _footerHeight = 0.0;
  var _emptyHeight = 0.0;
  var _done = false;

  int get paragraphsLaidOut => _heights.length;
  bool get isDone => _done;

  bool pump({int paragraphBudget = 8}) {
    if (_done) return true;
    var budget = paragraphBudget < 0 ? 0 : paragraphBudget;
    if (!_chromeReady && budget > 0) {
      _headerHeight = _measureHeader();
      _footerHeight = _measureFooter();
      _emptyHeight = _measureEmpty();
      _chromeReady = true;
      budget--;
    }
    while (_heights.length < paragraphs.length && budget > 0) {
      _heights.add(
        measureReaderText(
          text: paragraphs[_heights.length],
          style: _paint(bodyStyle),
          maxWidth: textWidth,
          align: textAlign,
          textScaler: textScaler,
        ),
      );
      budget--;
    }
    _done = _chromeReady && _heights.length >= paragraphs.length;
    return _done;
  }

  ReaderScrollLayout snapshot() {
    return ReaderScrollLayout(
      paragraphs: List.unmodifiable(paragraphs),
      paragraphHeights: List.unmodifiable(_heights),
      headerHeight: _headerHeight,
      footerHeight: _footerHeight,
      emptyHeight: _emptyHeight,
      charCount: charCount,
      paragraphSpacing: paragraphSpacing,
      textWidth: textWidth,
    );
  }

  double _measureHeader() {
    final titleHeight = chapterTitle.trim().isEmpty
        ? 0.0
        : measureReaderText(
            text: chapterTitle,
            style: _paint(titleStyle),
            maxWidth: textWidth,
            align: TextAlign.start,
            textScaler: textScaler,
          );
    final metaHeight = measureReaderText(
      text: metaLabel,
      style: _paint(metaStyle),
      maxWidth: math.max(textWidth - 40, 40),
      align: TextAlign.start,
      textScaler: textScaler,
    );
    return titleHeight + 10 + math.max(metaHeight, 2) + 20;
  }

  double _measureFooter() {
    final endHeight = measureReaderText(
      text: '本章完',
      style: _paint(const TextStyle(fontSize: 10.5, letterSpacing: 3)),
      maxWidth: textWidth,
      align: TextAlign.center,
      textScaler: textScaler,
    );
    var height = 26 + 1 + 10 + endHeight;
    if (hasNextChapter) {
      final hintHeight = measureReaderText(
        text: '左右滑动进入下一章',
        style: _paint(const TextStyle(fontSize: 10)),
        maxWidth: textWidth,
        align: TextAlign.center,
        textScaler: textScaler,
      );
      height += 4 + hintHeight;
    }
    return height;
  }

  double _measureEmpty() {
    final message = measureReaderText(
      text: '这一章没有正文',
      style: _paint(const TextStyle(fontSize: 13)),
      maxWidth: textWidth,
      align: TextAlign.center,
      textScaler: textScaler,
    );
    return 96 + message;
  }
}

double measureReaderText({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextAlign align,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    textScaler: textScaler,
    textWidthBasis: TextWidthBasis.parent,
  )..layout(maxWidth: math.max(maxWidth, 1));
  final height = painter.size.height;
  painter.dispose();
  return height;
}

/// Paragraph split plus the character count shown in the chapter header.
class PreparedReaderText {
  const PreparedReaderText({required this.paragraphs, required this.charCount});

  final List<String> paragraphs;
  final int charCount;
}

PreparedReaderText prepareReaderText(String text, double firstLineIndent) {
  return PreparedReaderText(
    paragraphs: ReaderPaginator.displayParagraphs(
      text,
      firstLineIndent: firstLineIndent,
    ),
    charCount: text.runes.length,
  );
}

/// Small LRU so leaving a chapter and coming back does not lay text out again.
class ReaderLayoutCache {
  static final pagination = _LruCache<ReaderPagination>(8);
  static final scroll = _LruCache<ReaderScrollLayout>(4);

  static void clear() {
    pagination.clear();
    scroll.clear();
  }
}

class _LruCache<T> {
  _LruCache(this.limit);

  final int limit;
  final Map<String, T> _values = {};
  final List<String> _order = [];

  T? get(String key) {
    final value = _values[key];
    if (value == null) return null;
    _order.remove(key);
    _order.add(key);
    return value;
  }

  void put(String key, T value) {
    _values[key] = value;
    _order.remove(key);
    _order.add(key);
    while (_order.length > limit) {
      _values.remove(_order.removeAt(0));
    }
  }

  void clear() {
    _values.clear();
    _order.clear();
  }
}
