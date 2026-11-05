import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation_app/app.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/screens/api_settings_screen.dart';
import 'package:translation_app/screens/library_screen.dart';
import 'package:translation_app/services/local_store.dart';
import 'package:translation_app/state/library_controller.dart';
import 'package:translation_app/state/settings_controller.dart';
import 'package:translation_app/state/translation_controller.dart';
import 'package:translation_app/state/tts_controller.dart';
import 'package:translation_app/widgets/tts_player_sheet.dart';

import 'support/fake_speech_engine.dart';

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_screen',
      title: '潮汐来信',
      author: '林川',
      fileName: '潮汐来信.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 160,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(
        id: 'chapter_0',
        index: 0,
        title: '第一章 潮声',
        text: '潮水在夜里涨起来。\n\n他坐在堤岸上，听远处传来汽笛声。',
      ),
      BookChapter(
        id: 'chapter_1',
        index: 1,
        title: '第二章 回信',
        text: '信纸被海风掀起一角。',
      ),
    ],
  );
}

void main() {
  late Directory tempDir;
  late LocalStore store;
  late SettingsController settings;
  late LibraryController library;
  late TranslationController translation;
  late TtsController tts;
  late FakeSpeechEngine speechEngine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('translation_screens_');
    store = LocalStore(tempDir);
    await store.ensureReady();
    settings = SettingsController(preferences: preferences);
    library = LibraryController(store: store);
    translation = TranslationController(store: store);
    speechEngine = FakeSpeechEngine();
    tts = TtsController(engine: speechEngine);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // A pending file handle on Windows should not fail a UI test.
    }
  });

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
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
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
          ChangeNotifierProvider<TtsController>.value(value: tts),
        ],
        child: MaterialApp(theme: AppTheme.build(), home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty library fits a phone and shows the import entry', (
    tester,
  ) async {
    await tester.runAsync(library.load);
    await pumpPhone(tester, LibraryScreen(onOpenSettings: () {}));

    expect(find.text('Beizx的阅读器'), findsOneWidget);
    expect(find.text('把一本小说留在书架'), findsOneWidget);
    expect(find.text('书架还空着'), findsOneWidget);
    expect(find.text('导入书籍'), findsOneWidget);
  });

  testWidgets('book card opens the reading-first detail page', (tester) async {
    await tester.runAsync(() async {
      await store.saveBook(_book());
      await store.saveLibrary([_book().meta]);
      await library.load();
      // Preload the parsed book so the route can open without waiting on
      // filesystem I/O inside the fake-async test zone.
      await library.openBook('book_screen');
    });
    await pumpPhone(tester, LibraryScreen(onOpenSettings: () {}));

    expect(find.text('潮汐来信'), findsOneWidget);
    await tester.tap(find.text('潮汐来信'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('书籍详情'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);
    expect(find.text('章节目录'), findsOneWidget);
    expect(find.text('第一章 潮声'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('翻译设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('翻译设置'), findsOneWidget);
    expect(find.text('开始翻译'), findsOneWidget);
  });

  testWidgets('API settings render on a narrow phone', (tester) async {
    await pumpPhone(tester, const ApiSettingsScreen());

    expect(find.text('让文字穿墙而过'), findsOneWidget);
    expect(find.text('有道智云密钥'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
  });

  testWidgets('TTS player exposes speed, sleep timer and transport', (
    tester,
  ) async {
    final book = _book();
    await tts.startChapter(book, 0);
    expect(speechEngine.spoken, isNotEmpty);

    await pumpPhone(
      tester,
      Scaffold(body: TtsPlayerSheet(book: book)),
    );

    expect(find.text('听书'), findsOneWidget);
    expect(find.text('第一章 潮声'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.text('定时关闭'), findsOneWidget);
    expect(find.text('自动下一章'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('root navigation separates reading from settings', (
    tester,
  ) async {
    await tester.runAsync(library.load);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      TranslationApp(
        settingsController: settings,
        libraryController: library,
        translationController: translation,
        ttsController: tts,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('阅读偏好'), findsOneWidget);
    expect(find.text('翻译接口'), findsOneWidget);
    expect(find.text('阅读是主角，翻译是随叫随到的工具'), findsOneWidget);

    await tester.tap(find.text('阅读偏好'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('排版'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    Navigator.of(tester.element(find.text('外观'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    expect(find.text('把一本小说留在书架'), findsOneWidget);
  });
}
