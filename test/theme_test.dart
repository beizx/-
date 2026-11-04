import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/theme/app_theme.dart';

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  test('theme is dark and uses the blue-purple palette', () {
    final theme = AppTheme.build();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.paper);
    expect(theme.colorScheme.primary, AppColors.accent);
  });

  test('text and semantic colors meet WCAG AA contrast', () {
    final pairs = <String, List<Color>>{
      'primary text on background': [AppColors.ink, AppColors.paper],
      'primary text on card': [AppColors.ink, AppColors.card],
      'secondary text on card': [AppColors.inkSoft, AppColors.card],
      'muted text on background': [AppColors.muted, AppColors.paper],
      'accent on background': [AppColors.accent, AppColors.paper],
      'accent on wash': [AppColors.accent, AppColors.accentWash],
      'success on wash': [AppColors.jade, AppColors.jadeWash],
      'warning on wash': [AppColors.gold, AppColors.goldWash],
      'danger on wash': [AppColors.danger, AppColors.dangerWash],
      'button label on primary': [Colors.white, AppColors.accentStrong],
    };

    for (final entry in pairs.entries) {
      final ratio = _contrast(entry.value[0], entry.value[1]);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} contrast is ${ratio.toStringAsFixed(2)}',
      );
    }
  });

  test('status bar and navigation bar use light icons on dark surfaces', () {
    expect(appSystemOverlayStyle.statusBarIconBrightness, Brightness.light);
    expect(
      appSystemOverlayStyle.systemNavigationBarIconBrightness,
      Brightness.light,
    );
    expect(appSystemOverlayStyle.systemNavigationBarColor, AppColors.paper);
  });
}
