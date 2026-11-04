import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  static const paper = Color(0xFF141221);
  static const paperDeep = Color(0xFF1B1830);
  static const card = Color(0xFF211D3A);
  static const ink = Color(0xFFF4F1FF);
  static const inkSoft = Color(0xFFD2CBE8);
  static const muted = Color(0xFFA79FC1);
  static const line = Color(0xFF3B3459);
  static const accent = Color(0xFFB9ACFF);
  static const accentStrong = Color(0xFF6E58DB);
  static const accentDeep = Color(0xFF4B3A96);
  static const accentWash = Color(0xFF2E2752);
  static const jade = Color(0xFF7BE0D3);
  static const jadeDeep = Color(0xFF25635E);
  static const jadeWash = Color(0xFF193836);
  static const gold = Color(0xFFF2C879);
  static const goldWash = Color(0xFF3A2F1B);
  static const danger = Color(0xFFFF98A6);
  static const dangerWash = Color(0xFF3B2030);
}

/// Light status-bar content for the dark blue-purple theme.
const SystemUiOverlayStyle appSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: AppColors.paper,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: Color(0x00000000),
);

abstract final class AppTheme {
  static const serif = 'serif';
  static const List<String> serifFallback = [
    'Songti SC',
    'STSong',
    'Noto Serif CJK SC',
    'Source Han Serif SC',
    'Noto Serif',
    'serif',
  ];

  static ThemeData build() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accentStrong,
          brightness: Brightness.dark,
          surface: AppColors.card,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.paper,
          primaryContainer: AppColors.accentWash,
          onPrimaryContainer: AppColors.ink,
          secondary: AppColors.jade,
          onSecondary: AppColors.paper,
          secondaryContainer: AppColors.jadeWash,
          onSecondaryContainer: AppColors.ink,
          tertiary: AppColors.gold,
          onTertiary: AppColors.paper,
          surface: AppColors.card,
          onSurface: AppColors.ink,
          surfaceContainerHighest: AppColors.paperDeep,
          outline: AppColors.line,
          outlineVariant: AppColors.line,
          error: AppColors.danger,
          onError: AppColors.paper,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: const TextStyle(
        fontFamily: serif,
        fontFamilyFallback: serifFallback,
        fontSize: 34,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: AppColors.ink,
      ),
      headlineMedium: const TextStyle(
        fontFamily: serif,
        fontFamilyFallback: serifFallback,
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.ink,
      ),
      headlineSmall: const TextStyle(
        fontFamily: serif,
        fontFamilyFallback: serifFallback,
        fontSize: 23,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleLarge: const TextStyle(
        fontFamily: serif,
        fontFamilyFallback: serifFallback,
        fontSize: 20,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleSmall: const TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: AppColors.inkSoft,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.7,
        color: AppColors.ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.6,
        color: AppColors.inkSoft,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 1.5,
        color: AppColors.muted,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: appSystemOverlayStyle,
        titleTextStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: serifFallback,
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentStrong,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paperDeep,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentWash,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.accent : AppColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? AppColors.accent : AppColors.muted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF312A52),
        contentTextStyle: const TextStyle(color: AppColors.ink, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.paperDeep,
        selectedColor: AppColors.accentWash,
        side: const BorderSide(color: AppColors.line),
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.accent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.paperDeep,
        circularTrackColor: AppColors.paperDeep,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.accent,
        dividerColor: AppColors.line,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkSoft,
        textColor: AppColors.ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentStrong,
        foregroundColor: Colors.white,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withValues(alpha: 0.32),
        selectionHandleColor: AppColors.accent,
      ),
    );
  }
}
