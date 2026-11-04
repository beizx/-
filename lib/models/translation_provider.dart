/// Metadata for translation engines shown in the API settings page.
class TranslationProviderInfo {
  const TranslationProviderInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.available,
  });

  final String id;
  final String name;
  final String description;
  final bool available;
}

abstract final class TranslationProviders {
  static const youdao = TranslationProviderInfo(
    id: 'youdao',
    name: '网易有道智云',
    description: '文本翻译 API v3，个人可申请免费额度',
    available: true,
  );

  static const List<TranslationProviderInfo> availableProviders = [youdao];

  static const List<TranslationProviderInfo> plannedProviders = [
    TranslationProviderInfo(
      id: 'baidu',
      name: '百度翻译开放平台',
      description: '通用文本翻译，接口位已预留',
      available: false,
    ),
    TranslationProviderInfo(
      id: 'deepl',
      name: 'DeepL API',
      description: '高质量欧洲语言翻译，接口位已预留',
      available: false,
    ),
    TranslationProviderInfo(
      id: 'google',
      name: 'Google Cloud Translation',
      description: '多语言云端翻译，接口位已预留',
      available: false,
    ),
  ];

  static TranslationProviderInfo byId(String id) {
    return [
      ...availableProviders,
      ...plannedProviders,
    ].firstWhere((provider) => provider.id == id, orElse: () => youdao);
  }
}
