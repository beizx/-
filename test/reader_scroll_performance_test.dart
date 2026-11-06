import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/reader_settings.dart';
import 'package:translation_app/screens/chapter_reader_screen.dart';
import 'package:translation_app/services/local_store.dart';
import 'package:translation_app/services/reader/reader_paginator.dart';
import 'package:translation_app/services/reader/reader_scroll_layout.dart';
import 'package:translation_app/state/library_controller.dart';
import 'package:translation_app/state/settings_controller.dart';
import 'package:translation_app/widgets/reader_content.dart';

String _longChapter({int paragraphs = 160}) {
  return List.generate(
    paragraphs,
    (index) => '第$index段。${'山风穿过灯塔，海面仍是雾。' * 6}',
  ).join('\n\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ReaderLayoutBudget.reset);
  tearDown(ReaderLayoutCache.clear);

  test('fraction reports skip sub-percent scroll noise', () {
    final start = DateTime(2026, 11, 6, 12);
    expect(
      shouldReportReadingFraction(
        previous: null,
        previousAt: null,
        next: 0.01,
        now: start,
      ),
      isTrue,
    );

    var previous = 0.01;
    var reports = 1;
    for (var step = 1; step <= 80; step++) {
      final next = 0.01 + step * 0.00005;
      final now = start.add(Duration(milliseconds: step));
      if (shouldReportReadingFraction(
        previous: previous,
        previousAt: start,
        next: next,
        now: now,
      )) {
        reports++;
        previous = next;
      }
    }
    expect(reports, 1);
    expect(
      shouldReportReadingFraction(
        previous: previous,
        previousAt: start,
        next: 0.02,
        now: start.add(const Duration(milliseconds: 10)),
      ),
      isTrue,
    );
  });

  testWidgets('a long chapter builds only the visible paragraphs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var reports = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: ReaderScrollView(
            chapterTitle: '长章',
            text: _longChapter(),
            isTranslation: false,
            reader: const ReaderPreferences(),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            initialFraction: 0,
            onFractionChanged: (_) => reports++,
            onToggleChrome: () {},
            hasNextChapter: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final built = find.byType(ReaderHighlightedParagraph).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(36));
    expect(find.textContaining('第0段'), findsWidgets);
    expect(find.textContaining('第150段'), findsNothing);
    expect(tester.takeException(), isNull);

    reports = 0;
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -1600),
      const Duration(milliseconds: 1000),
    );
    await tester.pumpAndSettle();

    final after = find.byType(ReaderHighlightedParagraph).evaluate().length;
    expect(after, lessThan(36));
    expect(reports, greaterThan(0));
    expect(reports, lessThan(25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('page mode paginates a long chapter across frames', (
    tester,
  ) async {
    ReaderLayoutBudget.syncParagraphLimit = 0;
    ReaderLayoutBudget.paragraphsPerFrame = 2;
    addTearDown(ReaderLayoutBudget.reset);

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final book = Book(
      meta: BookMeta(
        id: 'long_page',
        title: '分页',
        author: '未知作者',
        fileName: '分页.txt',
        format: BookFormat.txt,
        chapterCount: 1,
        charCount: 1000,
        importedAt: DateTime(2026, 11, 6),
      ),
      chapters: [
        BookChapter(id: 'c0', index: 0, title: '长章', text: _longChapter()),
      ],
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences: preferences);
    await settings.setReaderPreferences(
      const ReaderPreferences(mode: ReaderMode.page),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChapterReaderScreen(book: book, initialChapterIndex: 0),
        ),
      ),
    );
    await tester.pump();

    expect(ReaderPaginationJob.debugLastPumpLaidOut, inInclusiveRange(1, 2));
    expect(find.textContaining(RegExp(r'第 \d+ / \d+ 页')), findsNothing);

    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'第 \d+ / \d+ 页')), findsOneWidget);
    expect(find.textContaining('第0段'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading scroll does not rebuild the shelf', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences: preferences);
    final directory = Directory.systemTemp.createTempSync(
      'reader_scroll_perf_',
    );
    final store = LocalStore(directory);
    final library = LibraryController(store: store);
    final book = Book(
      meta: BookMeta(
        id: 'scroll_book',
        title: '滚动',
        author: '未知作者',
        fileName: '滚动.txt',
        format: BookFormat.txt,
        chapterCount: 1,
        charCount: 1000,
        importedAt: DateTime(2026, 11, 6),
      ),
      chapters: [
        BookChapter(id: 'c0', index: 0, title: '长章', text: _longChapter()),
      ],
    );
    await tester.runAsync(() async {
      await store.ensureReady();
      await store.saveBook(book);
      await store.saveLibrary([book.meta]);
      await library.load();
    });
    addTearDown(() {
      try {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      } on FileSystemException {
        // The temp directory can still be open on Windows.
      }
    });

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var notifications = 0;
    library.addListener(() => notifications++);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<LibraryController>.value(value: library),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: ChapterReaderScreen(book: book, initialChapterIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);

    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -900),
      const Duration(milliseconds: 400),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(notifications, 0);
    expect(library.progressFor('scroll_book'), isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(notifications, greaterThan(0));
  });
}
