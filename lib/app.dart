import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_info.dart';
import 'core/theme/app_theme.dart';
import 'screens/app_settings_screen.dart';
import 'screens/library_screen.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'state/translation_controller.dart';

class TranslationApp extends StatelessWidget {
  const TranslationApp({
    super.key,
    required this.settingsController,
    required this.libraryController,
    required this.translationController,
  });

  final SettingsController settingsController;
  final LibraryController libraryController;
  final TranslationController translationController;

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
