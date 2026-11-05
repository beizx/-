import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../models/tts_settings.dart';

/// One installed system voice.
class TtsVoiceInfo {
  const TtsVoiceInfo({required this.name, required this.locale});

  final String name;
  final String locale;

  String get label {
    final localeLabel = locale.replaceAll('_', '-');
    return '$localeLabel · $name';
  }
}

/// Thin seam over the platform TTS engine so the controller stays testable and
/// the UI never talks to `flutter_tts` directly.
abstract interface class SpeechEngine {
  /// Prepares rate / pitch / voice. Called before every utterance so that
  /// changing speed mid-book takes effect on the next paragraph.
  Future<void> prepare(TtsPreferences preferences);

  Future<void> speak(String text);

  Future<void> pause();

  Future<void> stop();

  Future<List<TtsVoiceInfo>> voices();

  /// Handlers are fired from platform callbacks.
  void setHandlers({VoidCallback? onComplete, VoidCallback? onCancel});
}

/// [SpeechEngine] backed by the `flutter_tts` plugin.
class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  List<TtsVoiceInfo>? _cachedVoices;

  @override
  Future<void> prepare(TtsPreferences preferences) async {
    await _tts.setSpeechRate(preferences.rate);
    await _tts.setPitch(preferences.pitch);
    await _tts.setVolume(1.0);
    final voice = preferences.voiceName;
    if (voice != null && voice.isNotEmpty) {
      try {
        await _tts.setVoice({'name': voice, 'locale': preferences.languageCode});
        return;
      } on Object {
        // Fall through to the locale-only path below.
      }
    }
    try {
      await _tts.setLanguage(preferences.languageCode);
    } on Object {
      // No installed voice for this locale: keep the platform default.
    }
  }

  @override
  Future<void> speak(String text) async {
    // Android queues utterances; awaiting completion keeps segment order
    // deterministic on both platforms.
    await _tts.speak(text);
  }

  @override
  Future<void> pause() async {
    await _tts.pause();
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<List<TtsVoiceInfo>> voices() async {
    final cached = _cachedVoices;
    if (cached != null) return cached;
    try {
      final raw = await _tts.getVoices;
      final parsed = <TtsVoiceInfo>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final name = item['name']?.toString();
            final locale = item['locale']?.toString();
            if (name != null && name.isNotEmpty) {
              parsed.add(
                TtsVoiceInfo(name: name, locale: locale ?? ''),
              );
            }
          }
        }
      }
      _cachedVoices = parsed;
      return parsed;
    } on Object {
      return const [];
    }
  }

  @override
  void setHandlers({VoidCallback? onComplete, VoidCallback? onCancel}) {
    _tts.setCompletionHandler(() => onComplete?.call());
    _tts.setCancelHandler(() => onCancel?.call());
    _tts.setErrorHandler((dynamic _) => onCancel?.call());
  }
}
