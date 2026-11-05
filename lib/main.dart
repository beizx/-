import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'services/local_store.dart';
import 'services/reader/audio_service_media_session.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'state/translation_controller.dart';
import 'state/tts_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(appSystemOverlayStyle);
  try {
    final preferences = await SharedPreferences.getInstance();
    final store = await LocalStore.open();
    final settings = SettingsController(preferences: preferences);
    final library = LibraryController(store: store);
    final translation = TranslationController(
      store: store,
      onTranslationsChanged: library.refreshTranslatedLanguages,
    );

    // Lock screen / notification controls. Returns null where the platform has
    // no media session, in which case 听书 keeps running in-app only.
    final mediaSession = await initTtsMediaSession();

    await Future.wait([settings.load(), library.load()]);

    runApp(
      TranslationApp(
        settingsController: settings,
        libraryController: library,
        translationController: translation,
        ttsController: TtsController(
          preferences: settings.ttsPreferences,
          mediaSession: mediaSession,
        ),
      ),
    );
  } on Object catch (error) {
    runApp(BootstrapErrorApp(message: error.toString()));
  }
}

/// Shown only if the local workspace or plugins cannot be initialized.
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 36,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Beizx的阅读器启动失败',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '本地存储或系统组件未能初始化。请重启应用后再试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
