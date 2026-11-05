import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_info.dart';
import 'core/theme/app_theme.dart';
import 'screens/app_settings_screen.dart';
import 'screens/library_screen.dart';
import 'services/import/book_importer.dart';
import 'services/import/external_file_service.dart';
import 'services/reader/background_playback_guide.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'state/translation_controller.dart';
import 'state/tts_controller.dart';

class TranslationApp extends StatelessWidget {
  const TranslationApp({
    super.key,
    required this.settingsController,
    required this.libraryController,
    required this.translationController,
    required this.ttsController,
  });

  final SettingsController settingsController;
  final LibraryController libraryController;
  final TranslationController translationController;
  final TtsController ttsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<LibraryController>.value(
          value: libraryController,
        ),
        ChangeNotifierProvider<TranslationController>.value(
          value: translationController,
        ),
        ChangeNotifierProvider<TtsController>.value(value: ttsController),
      ],
      child: MaterialApp(
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        themeMode: ThemeMode.dark,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RootShell(),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  late final ExternalFileService _externalFiles = ExternalFileService();
  TtsController? _tts;
  bool _ttsActive = false;

  @override
  void initState() {
    super.initState();
    _externalFiles.bind(_handleIncomingFile);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _noteInterruptedPlayback();
      final pending = await _externalFiles.takePending();
      if (pending != null) await _handleIncomingFile(pending);
      await _externalFiles.flushQueue();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tts = context.read<TtsController>();
    if (!identical(_tts, tts)) {
      _tts?.removeListener(_rememberListening);
      _tts = tts;
      _ttsActive = tts.isActive;
      tts.addListener(_rememberListening);
    }
  }

  @override
  void dispose() {
    _tts?.removeListener(_rememberListening);
    super.dispose();
  }

  void _rememberListening() {
    final tts = _tts;
    final settings = context.read<SettingsController>();
    if (tts == null || tts.isActive == _ttsActive) return;
    _ttsActive = tts.isActive;
    unawaited(settings.setTtsWasActive(_ttsActive));
  }

  Future<void> _noteInterruptedPlayback() async {
    if (!mounted) return;
    final settings = context.read<SettingsController>();
    if (!settings.ttsWasActive) return;
    await settings.setTtsWasActive(false);
    if (!mounted) return;
    await BackgroundPlaybackGuide.maybeShow(
      context,
      dismissedForever: settings.backgroundPlaybackGuideDismissed,
      onDismissForever: settings.dismissBackgroundPlaybackGuide,
      becauseInterrupted: true,
    );
  }

  /// Imports a document another app opened with us and jumps to the shelf.
  Future<void> _handleIncomingFile(IncomingFile file) async {
    if (!mounted) return;
    final library = context.read<LibraryController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!ExternalFileService.supportedExtensions.contains(file.extension)) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('目前只支持 TXT 和 EPUB 文件')),
      );
      return;
    }
    try {
      final book = await library.importFromPath(
        path: file.path,
        fileName: file.name,
      );
      if (!mounted || book == null) return;
      setState(() => _index = 0);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已导入《${book.meta.title}》'),
            duration: const Duration(seconds: 2),
          ),
        );
      // The library keeps its own copy, so the cache file is disposable.
      unawaited(_discardCacheCopy(file.path));
    } on BookImportException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text('打开文件失败：$error')));
    }
  }

  Future<void> _discardCacheCopy(String path) async {
    try {
      final handle = File(path);
      if (await handle.exists()) await handle.delete();
    } on Object {
      // A leftover cache file is harmless.
    }
  }

  void _selectTab(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) {
          _selectTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: IndexedStack(
          index: _index,
          children: [
            LibraryScreen(onOpenSettings: () => _selectTab(1)),
            const AppSettingsScreen(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: '书架',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
