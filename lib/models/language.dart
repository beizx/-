/// App languages and the extension point for adding more.
///
/// To add a language:
/// 1. Add a const [AppLanguage] to the registry.
/// 2. Add its provider code under `providerCodes` for each translation engine.
/// 3. Add it to [sourceOptions] and/or [targetOptions].
///
/// UI menus are generated from these lists, so no screen changes are required.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.label,
    required this.nativeLabel,
    required this.providerCodes,
    this.isAuto = false,
  });

  /// Stable internal code, also persisted in settings and records.
  final String code;

  /// Chinese display name used throughout the UI.
  final String label;

  /// Language name written in the language itself.
  final String nativeLabel;

  /// Provider-specific language code, keyed by provider id.
  final Map<String, String> providerCodes;

  /// The auto-detect pseudo language; never a valid target.
  final bool isAuto;

  String providerCode(String providerId) => providerCodes[providerId] ?? code;

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

abstract final class Languages {
  static const auto = AppLanguage(
    code: 'auto',
    label: '自动识别',
    nativeLabel: 'Auto',
    providerCodes: {
      'youdao': 'auto',
      'baidu': 'auto',
      'deepl': '',
      'google': '',
    },
    isAuto: true,
  );

  static const zh = AppLanguage(
    code: 'zh',
    label: '中文',
    nativeLabel: '中文',
    providerCodes: {
      'youdao': 'zh-CHS',
      'baidu': 'zh',
      'deepl': 'ZH',
      'google': 'zh-CN',
    },
  );

  static const ja = AppLanguage(
    code: 'ja',
    label: '日语',
    nativeLabel: '日本語',
    providerCodes: {
      'youdao': 'ja',
      'baidu': 'jp',
      'deepl': 'JA',
      'google': 'ja',
    },
  );

  static const ko = AppLanguage(
    code: 'ko',
    label: '韩语',
    nativeLabel: '한국어',
    providerCodes: {
      'youdao': 'ko',
      'baidu': 'kor',
      'deepl': 'KO',
      'google': 'ko',
    },
  );

  static const en = AppLanguage(
    code: 'en',
    label: '英语',
    nativeLabel: 'English',
    providerCodes: {
      'youdao': 'en',
      'baidu': 'en',
      'deepl': 'EN',
      'google': 'en',
    },
  );

  /// Extend this list to expose a new language in both pickers.
  static const List<AppLanguage> all = [auto, zh, ja, ko, en];

  static const List<AppLanguage> sourceOptions = all;

  static const List<AppLanguage> targetOptions = [zh, ja, ko, en];

  static AppLanguage byCode(String? code, {AppLanguage fallback = zh}) {
    if (code == null) return fallback;
    return all.firstWhere(
      (language) => language.code == code,
      orElse: () => fallback,
    );
  }

  static AppLanguage sourceByCode(String? code) => byCode(code, fallback: auto);

  static String displayName(String? code) => byCode(code).label;
}
