import 'package:flutter/material.dart';

/// Reading surfaces offered in the reader. Each skin carries its own
/// background and text colors so contrast stays comfortable per theme.
enum ReaderSkin {
  night(
    label: '夜色',
    background: Color(0xFF141221),
    text: Color(0xFFF4F1FF),
    secondary: Color(0xFFA79FC1),
    chrome: Color(0xFF211D3A),
    line: Color(0xFF3B3459),
    accent: Color(0xFFB9ACFF),
  ),
  paper(
    label: '纸白',
    background: Color(0xFFFAF7F0),
    text: Color(0xFF23202B),
    secondary: Color(0xFF6C6577),
    chrome: Color(0xFFF1ECE1),
    line: Color(0xFFDDD5C6),
    accent: Color(0xFF5B49C4),
  ),
  sepia(
    label: '羊皮',
    background: Color(0xFFF2E7D3),
    text: Color(0xFF3E3324),
    secondary: Color(0xFF7C6B52),
    chrome: Color(0xFFE8DAC0),
    line: Color(0xFFD3C2A4),
    accent: Color(0xFF8A5A28),
  ),
  mint(
    label: '护眼',
    background: Color(0xFF17211D),
    text: Color(0xFFE4F1E8),
    secondary: Color(0xFF95AFA1),
    chrome: Color(0xFF1E2B25),
    line: Color(0xFF31443A),
    accent: Color(0xFF7BE0D3),
  );

  const ReaderSkin({
    required this.label,
    required this.background,
    required this.text,
    required this.secondary,
    required this.chrome,
    required this.line,
    required this.accent,
  });

  final String label;
  final Color background;
  final Color text;
  final Color secondary;
  final Color chrome;
  final Color line;
  final Color accent;

  bool get isDark => background.computeLuminance() < 0.5;

  static ReaderSkin byName(String? name) {
    return values.firstWhere(
      (skin) => skin.name == name,
      orElse: () => ReaderSkin.night,
    );
  }
}

/// Scroll mode is a vertical flow of paragraphs inside a chapter; page mode
/// paginates the chapter so it can be turned like a paper book.
enum ReaderMode {
  scroll('滚动阅读', '上下滚动，左右滑动切换章节'),
  page('翻页阅读', '自动分页，左右翻页，像纸质书一样');

  const ReaderMode(this.label, this.description);

  final String label;
  final String description;

  static ReaderMode byName(String? name) {
    return values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ReaderMode.scroll,
    );
  }
}

enum ReaderFontWeight {
  regular('常规', 400),
  medium('适中', 500),
  semibold('偏粗', 600);

  const ReaderFontWeight(this.label, this.value);

  final String label;
  final int value;

  FontWeight get fontWeight => switch (this) {
    ReaderFontWeight.regular => FontWeight.w400,
    ReaderFontWeight.medium => FontWeight.w500,
    ReaderFontWeight.semibold => FontWeight.w600,
  };

  static ReaderFontWeight byName(String? name) {
    return values.firstWhere(
      (weight) => weight.name == name,
      orElse: () => ReaderFontWeight.regular,
    );
  }
}

enum ReaderTurnAnimation {
  slide('滑动'),
  none('无动画');

  const ReaderTurnAnimation(this.label);

  final String label;

  static ReaderTurnAnimation byName(String? name) {
    return values.firstWhere(
      (animation) => animation.name == name,
      orElse: () => ReaderTurnAnimation.slide,
    );
  }
}

/// Immutable reader preferences, persisted as a single JSON object.
///
/// Defaults follow the app's own deep blue-purple night theme; the layout
/// controls mirror the conventions of dedicated novel readers.
class ReaderPreferences {
  const ReaderPreferences({
    this.fontSize = 18.0,
    this.lineHeight = 1.95,
    this.skin = ReaderSkin.night,
    this.serif = true,
    this.mode = ReaderMode.scroll,
    this.fontWeight = ReaderFontWeight.regular,
    this.paragraphSpacing = 12.0,
    this.firstLineIndent = 2.0,
    this.horizontalMargin = 24.0,
    this.topMargin = 18.0,
    this.bottomMargin = 28.0,
    this.keepScreenOn = false,
    this.hideStatusBar = true,
    this.tapToTurnPage = true,
    this.turnAnimation = ReaderTurnAnimation.slide,
    this.showClock = true,
    this.showChapterTitle = true,
    this.showProgress = true,
    this.showPageNumber = true,
    this.justify = true,
  });

  static const minFontSize = 14.0;
  static const maxFontSize = 28.0;
  static const minLineHeight = 1.4;
  static const maxLineHeight = 2.8;
  static const minParagraphSpacing = 0.0;
  static const maxParagraphSpacing = 28.0;
  static const minFirstLineIndent = 0.0;
  static const maxFirstLineIndent = 2.0;
  static const minHorizontalMargin = 12.0;
  static const maxHorizontalMargin = 48.0;
  static const minVerticalMargin = 8.0;
  static const maxVerticalMargin = 64.0;

  final double fontSize;
  final double lineHeight;
  final ReaderSkin skin;
  final bool serif;
  final ReaderMode mode;
  final ReaderFontWeight fontWeight;
  final double paragraphSpacing;
  final double firstLineIndent;
  final double horizontalMargin;
  final double topMargin;
  final double bottomMargin;
  final bool keepScreenOn;
  final bool hideStatusBar;
  final bool tapToTurnPage;
  final ReaderTurnAnimation turnAnimation;
  final bool showClock;
  final bool showChapterTitle;
  final bool showProgress;
  final bool showPageNumber;
  final bool justify;

  /// Style-only fingerprint used to invalidate pagination caches.
  String get layoutSignature => [
    fontSize.toStringAsFixed(1),
    lineHeight.toStringAsFixed(2),
    fontWeight.value,
    serif ? 'serif' : 'sans',
    firstLineIndent.toStringAsFixed(1),
    justify ? 'justify' : 'start',
  ].join('|');

  ReaderPreferences normalized() {
    return ReaderPreferences(
      fontSize: fontSize.clamp(minFontSize, maxFontSize),
      lineHeight: lineHeight.clamp(minLineHeight, maxLineHeight),
      skin: skin,
      serif: serif,
      mode: mode,
      fontWeight: fontWeight,
      paragraphSpacing: paragraphSpacing.clamp(
        minParagraphSpacing,
        maxParagraphSpacing,
      ),
      firstLineIndent: firstLineIndent.clamp(
        minFirstLineIndent,
        maxFirstLineIndent,
      ),
      horizontalMargin: horizontalMargin.clamp(
        minHorizontalMargin,
        maxHorizontalMargin,
      ),
      topMargin: topMargin.clamp(minVerticalMargin, maxVerticalMargin),
      bottomMargin: bottomMargin.clamp(minVerticalMargin, maxVerticalMargin),
      keepScreenOn: keepScreenOn,
      hideStatusBar: hideStatusBar,
      tapToTurnPage: tapToTurnPage,
      turnAnimation: turnAnimation,
      showClock: showClock,
      showChapterTitle: showChapterTitle,
      showProgress: showProgress,
      showPageNumber: showPageNumber,
      justify: justify,
    );
  }

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'skin': skin.name,
    'serif': serif,
    'mode': mode.name,
    'fontWeight': fontWeight.name,
    'paragraphSpacing': paragraphSpacing,
    'firstLineIndent': firstLineIndent,
    'horizontalMargin': horizontalMargin,
    'topMargin': topMargin,
    'bottomMargin': bottomMargin,
    'keepScreenOn': keepScreenOn,
    'hideStatusBar': hideStatusBar,
    'tapToTurnPage': tapToTurnPage,
    'turnAnimation': turnAnimation.name,
    'showClock': showClock,
    'showChapterTitle': showChapterTitle,
    'showProgress': showProgress,
    'showPageNumber': showPageNumber,
    'justify': justify,
  };

  factory ReaderPreferences.fromJson(Map<String, Object?> json) {
    const defaults = ReaderPreferences();
    double number(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return ReaderPreferences(
      fontSize: number('fontSize', defaults.fontSize),
      lineHeight: number('lineHeight', defaults.lineHeight),
      skin: ReaderSkin.byName(json['skin'] as String?),
      serif: flag('serif', defaults.serif),
      mode: ReaderMode.byName(json['mode'] as String?),
      fontWeight: ReaderFontWeight.byName(json['fontWeight'] as String?),
      paragraphSpacing: number('paragraphSpacing', defaults.paragraphSpacing),
      firstLineIndent: number('firstLineIndent', defaults.firstLineIndent),
      horizontalMargin: number('horizontalMargin', defaults.horizontalMargin),
      topMargin: number('topMargin', defaults.topMargin),
      bottomMargin: number('bottomMargin', defaults.bottomMargin),
      keepScreenOn: flag('keepScreenOn', defaults.keepScreenOn),
      hideStatusBar: flag('hideStatusBar', defaults.hideStatusBar),
      tapToTurnPage: flag('tapToTurnPage', defaults.tapToTurnPage),
      turnAnimation: ReaderTurnAnimation.byName(
        json['turnAnimation'] as String?,
      ),
      showClock: flag('showClock', defaults.showClock),
      showChapterTitle: flag('showChapterTitle', defaults.showChapterTitle),
      showProgress: flag('showProgress', defaults.showProgress),
      showPageNumber: flag('showPageNumber', defaults.showPageNumber),
      justify: flag('justify', defaults.justify),
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPreferences &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.skin == skin &&
      other.serif == serif &&
      other.mode == mode &&
      other.fontWeight == fontWeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.firstLineIndent == firstLineIndent &&
      other.horizontalMargin == horizontalMargin &&
      other.topMargin == topMargin &&
      other.bottomMargin == bottomMargin &&
      other.keepScreenOn == keepScreenOn &&
      other.hideStatusBar == hideStatusBar &&
      other.tapToTurnPage == tapToTurnPage &&
      other.turnAnimation == turnAnimation &&
      other.showClock == showClock &&
      other.showChapterTitle == showChapterTitle &&
      other.showProgress == showProgress &&
      other.showPageNumber == showPageNumber &&
      other.justify == justify;

  @override
  int get hashCode => Object.hashAll([
    fontSize,
    lineHeight,
    skin,
    serif,
    mode,
    fontWeight,
    paragraphSpacing,
    firstLineIndent,
    horizontalMargin,
    topMargin,
    bottomMargin,
    keepScreenOn,
    hideStatusBar,
    tapToTurnPage,
    turnAnimation,
    showClock,
    showChapterTitle,
    showProgress,
    showPageNumber,
    justify,
  ]);

  ReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderSkin? skin,
    bool? serif,
    ReaderMode? mode,
    ReaderFontWeight? fontWeight,
    double? paragraphSpacing,
    double? firstLineIndent,
    double? horizontalMargin,
    double? topMargin,
    double? bottomMargin,
    bool? keepScreenOn,
    bool? hideStatusBar,
    bool? tapToTurnPage,
    ReaderTurnAnimation? turnAnimation,
    bool? showClock,
    bool? showChapterTitle,
    bool? showProgress,
    bool? showPageNumber,
    bool? justify,
  }) {
    return ReaderPreferences(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      skin: skin ?? this.skin,
      serif: serif ?? this.serif,
      mode: mode ?? this.mode,
      fontWeight: fontWeight ?? this.fontWeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      topMargin: topMargin ?? this.topMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      hideStatusBar: hideStatusBar ?? this.hideStatusBar,
      tapToTurnPage: tapToTurnPage ?? this.tapToTurnPage,
      turnAnimation: turnAnimation ?? this.turnAnimation,
      showClock: showClock ?? this.showClock,
      showChapterTitle: showChapterTitle ?? this.showChapterTitle,
      showProgress: showProgress ?? this.showProgress,
      showPageNumber: showPageNumber ?? this.showPageNumber,
      justify: justify ?? this.justify,
    );
  }
}
