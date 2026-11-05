import 'dart:convert';

/// Persisted 听书 preferences.
///
/// Sleep timers are *not* stored here: they belong to a single listening
/// session, so [TtsController] keeps them in memory.
class TtsPreferences {
  const TtsPreferences({
    this.rate = 0.5,
    this.pitch = 1.0,
    this.voiceName,
    this.languageCode = 'zh-CN',
    this.autoNextChapter = true,
  });

  /// Platform speech rates: 0.5 is roughly a natural reading pace, so the UI
  /// exposes 0.7x–2.4x of this baseline.
  static const minRate = 0.25;
  static const maxRate = 1.5;
  static const minPitch = 0.6;
  static const maxPitch = 1.4;

  final double rate;
  final double pitch;
  final String? voiceName;
  final String languageCode;
  final bool autoNextChapter;

  /// Speed steps shown as chips in the player.
  static const speedChoices = <double>[0.35, 0.5, 0.65, 0.8, 1.0, 1.2];

  static String labelForRate(double rate) {
    final factor = rate * 2;
    final text = factor.toStringAsFixed(2);
    final trimmed = text.endsWith('0') ? text.substring(0, text.length - 1) : text;
    return '${trimmed}x';
  }

  TtsPreferences normalized() {
    return TtsPreferences(
      rate: rate.clamp(minRate, maxRate),
      pitch: pitch.clamp(minPitch, maxPitch),
      voiceName: (voiceName?.trim().isEmpty ?? true) ? null : voiceName,
      languageCode: languageCode.trim().isEmpty ? 'zh-CN' : languageCode,
      autoNextChapter: autoNextChapter,
    );
  }

  Map<String, Object?> toJson() => {
    'rate': rate,
    'pitch': pitch,
    'voiceName': voiceName,
    'languageCode': languageCode,
    'autoNextChapter': autoNextChapter,
  };

  factory TtsPreferences.fromJson(Map<String, Object?> json) {
    const defaults = TtsPreferences();
    double number(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final rawVoice = json['voiceName'];
    final rawLanguage = json['languageCode'];
    return TtsPreferences(
      rate: number('rate', defaults.rate),
      pitch: number('pitch', defaults.pitch),
      voiceName: rawVoice is String && rawVoice.trim().isNotEmpty
          ? rawVoice
          : null,
      languageCode: rawLanguage is String && rawLanguage.trim().isNotEmpty
          ? rawLanguage
          : defaults.languageCode,
      autoNextChapter: flag('autoNextChapter', defaults.autoNextChapter),
    ).normalized();
  }

  static TtsPreferences decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const TtsPreferences();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return TtsPreferences.fromJson(Map<String, Object?>.from(decoded));
      }
    } on Object {
      // Corrupted preferences fall back to defaults instead of failing boot.
    }
    return const TtsPreferences();
  }

  String encode() => jsonEncode(toJson());

  TtsPreferences copyWith({
    double? rate,
    double? pitch,
    String? voiceName,
    bool clearVoice = false,
    String? languageCode,
    bool? autoNextChapter,
  }) {
    return TtsPreferences(
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
      languageCode: languageCode ?? this.languageCode,
      autoNextChapter: autoNextChapter ?? this.autoNextChapter,
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      other is TtsPreferences &&
      other.rate == rate &&
      other.pitch == pitch &&
      other.voiceName == voiceName &&
      other.languageCode == languageCode &&
      other.autoNextChapter == autoNextChapter;

  @override
  int get hashCode =>
      Object.hash(rate, pitch, voiceName, languageCode, autoNextChapter);
}
