import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/screens/multilingual_dedupe_screen.dart';
import 'package:translation_app/services/local_store.dart';
import 'package:translation_app/state/library_controller.dart';
import 'package:translation_app/state/settings_controller.dart';

Book _bilingualBook() {
  return Book(
    meta: BookMeta(
      id: 'book_bilingual',
      title: '双语对照示例',
      author: '示例作者',
      fileName: '双语对照示例.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 120,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(
        id: 'chapter_0',
        index: 0,
        title: '第一章 海岸',
        text: '海は静かだった。\n大海很安静。\n彼女は窓の外を見ていた。\n她望着窗外。',
      ),
      BookChapter(
        id: 'chapter_1',
        index: 1,
        title: '第二章 灯塔',
        text: 'The lighthouse blinked twice.\n灯塔闪了两次。\n바람이 차가웠다.\n风很冷。',
      ),
    ],
  );
}

void main() {
  late Directory tempDir;
  late SettingsController settings;
  late LibraryController library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tempDir = Directory.systemTemp.createTempSync('dedupe_screen_');
    final store = LocalStore(tempDir);
    settings = SettingsController(preferences: preferences);
    library = LibraryController(store: store);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; this fixture writes no files.
    }
  });

  testWidgets('dedupe screen analyzes and lets user change language', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<LibraryController>.value(value: library),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: MultilingualDedupeScreen(book: _bilingualBook()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('同一段话，只留一边'), findsOneWidget);
    expect(find.text('疑似对照 4 组'), findsOneWidget);
    expect(find.text('保留 · 中文'), findsWidgets);
    expect(find.text('移除 · 日语'), findsWidgets);
    expect(find.text('仅加入书库'), findsOneWidget);
    expect(find.text('生成并导出'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '日语'));
    await tester.pumpAndSettle();

    expect(find.text('疑似对照 2 组'), findsOneWidget);
    expect(find.text('保留 · 日语'), findsWidgets);
    expect(find.text('移除 · 中文'), findsWidgets);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('将移除 1 段'), findsOneWidget);
  });
}
