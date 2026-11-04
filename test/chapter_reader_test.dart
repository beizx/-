import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/models/reader_settings.dart';
import 'package:translation_app/screens/chapter_reader_screen.dart';
import 'package:translation_app/services/local_store.dart';
import 'package:translation_app/state/library_controller.dart';
import 'package:translation_app/state/settings_controller.dart';

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_reader',
      title: '阅读测试',
      author: '未知作者',
      fileName: '阅读测试.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 20,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(
        id: 'chapter_0',
        index: 0,
        title: '第一章 起雾',
        text: '海面起了雾。\n\n灯塔仍亮着。',
      ),
      BookChapter(id: 'chapter_1', index: 1, title: '第二章 归航', text: '船在清晨靠岸。'),
    ],
  );
}

TranslationRecord _record() {
  return TranslationRecord(
    bookId: 'book_reader',
    sourceLanguage: 'zh',
    targetLanguage: Languages.ja.code,
    providerId: 'youdao',
    createdAt: DateTime(2026, 11, 4),
    chapters: const [
      TranslatedChapter(
        chapterId: 'chapter_0',
        chapterIndex: 0,
        title: '第一章 起雾',
        text: '海面に霧が立ちこめた。\n\n灯台はまだ灯っている。',
      ),
      TranslatedChapter(
        chapterId: 'chapter_1',
        chapterIndex: 1,
        title: '第二章 归航',
        text: '船は早朝に岸へ着いた。',
      ),
    ],
  );
}

void main() {
  testWidgets('reader shows original, translation and chapter navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChapterReaderScreen(
          book: _book(),
          initialChapterIndex: 0,
          translation: _record(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The reader opens in immersive mode; tap the page to reveal the chrome.
    await tester.tapAt(const Offset(196, 500));
    await tester.pumpAndSettle();

    expect(find.text('第 1 / 2 章'), findsOneWidget);
    expect(find.text('原文'), findsOneWidget);
    expect(find.text('译文 · 日语'), findsOneWidget);
    expect(find.textContaining('海面起了雾'), findsOneWidget);
    expect(find.text('第一章 起雾'), findsWidgets);

    await tester.tap(find.text('译文 · 日语'));
    await tester.pumpAndSettle();
    expect(find.textContaining('海面に霧'), findsOneWidget);

    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 章'), findsOneWidget);
    expect(find.text('第二章 归航'), findsWidgets);
    expect(find.textContaining('船は早朝に'), findsOneWidget);
  });

  testWidgets('supports chapter swipes, toc, settings and bookmarks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences: preferences);
    final directory = Directory.systemTemp.createTempSync('reader_progress_');
    final store = LocalStore(directory);
    final library = LibraryController(store: store);
    await tester.runAsync(() async {
      await store.ensureReady();
      await store.saveBook(_book());
      await store.saveLibrary([_book().meta]);
      await library.load();
    });

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      try {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold a handle to the temp store.
      }
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<LibraryController>.value(value: library),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChapterReaderScreen(book: _book(), initialChapterIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 章'), findsOneWidget);
    expect(library.progressFor('book_reader')?.chapterIndex, 1);

    await tester.tapAt(const Offset(196, 500));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.text('阅读导航'), findsOneWidget);
    expect(find.text('目录 2'), findsOneWidget);
    await tester.tap(find.text('第一章 起雾').last);
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 章'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('排版'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    await tester.tap(find.text('纸白'));
    await tester.pumpAndSettle();
    expect(settings.readerPreferences.skin, ReaderSkin.paper);
    Navigator.of(tester.element(find.text('纸白'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加书签'));
    await tester.pumpAndSettle();
    expect(library.bookmarksFor('book_reader'), hasLength(1));

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('海面起了雾'), findsWidgets);
    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();
    expect(library.bookmarksFor('book_reader'), isEmpty);
  });

  testWidgets('page mode paginates and turns chapters from the edge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences: preferences);
    await settings.setReaderPreferences(
      const ReaderPreferences(mode: ReaderMode.page),
    );

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChapterReaderScreen(
            book: _book(),
            initialChapterIndex: 0,
            translation: _record(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 / 1 页'), findsOneWidget);
    expect(find.textContaining('海面起了雾'), findsOneWidget);

    await tester.tapAt(const Offset(196, 500));
    await tester.pumpAndSettle();

    // Tapping the right zone advances to the next chapter when the current
    // chapter has a single page.
    await tester.tapAt(const Offset(360, 420));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 章'), findsOneWidget);
  });

  testWidgets('page mode splits a long chapter and swipes between pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences: preferences);
    await settings.setReaderPreferences(
      const ReaderPreferences(mode: ReaderMode.page),
    );

    final longText = List.generate(
      40,
      (index) => '第${index + 1}段。海风穿过灯塔，潮水一遍遍漫过礁石。',
    ).join('\n');
    final book = Book(
      meta: BookMeta(
        id: 'book_long',
        title: '长篇测试',
        author: '未知作者',
        fileName: '长篇测试.txt',
        format: BookFormat.txt,
        chapterCount: 1,
        charCount: longText.length,
        importedAt: DateTime(2026, 11, 4),
      ),
      chapters: [
        BookChapter(id: 'long_0', index: 0, title: '第一章 长夜', text: longText),
      ],
    );

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChapterReaderScreen(book: book, initialChapterIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'^第 1 / \d+ 页$')), findsOneWidget);
    expect(find.textContaining('海风穿过灯塔'), findsWidgets);

    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^第 2 / \d+ 页$')), findsOneWidget);
  });

  testWidgets('starts on the original when there is no translation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChapterReaderScreen(book: _book(), initialChapterIndex: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('译文 · 日语'), findsNothing);
    expect(find.text('原文'), findsNothing);
    expect(find.textContaining('海面起了雾'), findsOneWidget);
  });
}
