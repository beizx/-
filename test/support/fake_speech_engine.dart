import 'package:flutter/foundation.dart';
import 'package:translation_app/models/tts_settings.dart';
import 'package:translation_app/services/reader/speech_engine.dart';

/// Deterministic [SpeechEngine] for unit and widget tests.
///
/// Tests drive playback explicitly with [finishCurrent] so they never depend on
/// real audio or platform channels.
class FakeSpeechEngine implements SpeechEngine {
  final List<String> spoken = [];
  final List<TtsPreferences> prepared = [];
  int stopCalls = 0;
  int pauseCalls = 0;
  bool failOnSpeak = false;
  List<TtsVoiceInfo> voicesToReturn = const [
    TtsVoiceInfo(name: 'zh-cn-x-1', locale: 'zh-CN'),
    TtsVoiceInfo(name: 'ja-jp-x-1', locale: 'ja-JP'),
  ];

  VoidCallback? _onComplete;
  VoidCallback? _onCancel;

  String? get lastSpoken => spoken.isEmpty ? null : spoken.last;

  @override
  Future<void> prepare(TtsPreferences preferences) async {
    prepared.add(preferences);
  }

  @override
  Future<void> speak(String text) async {
    if (failOnSpeak) throw StateError('speech failed');
    spoken.add(text);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<List<TtsVoiceInfo>> voices() async => voicesToReturn;

  @override
  void setHandlers({VoidCallback? onComplete, VoidCallback? onCancel}) {
    _onComplete = onComplete;
    _onCancel = onCancel;
  }

  /// Simulates the platform reporting the current utterance as finished.
  void finishCurrent() => _onComplete?.call();

  /// Simulates the platform cancelling the current utterance.
  void cancelCurrent() => _onCancel?.call();
}
