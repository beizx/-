/// Contract every translation service must satisfy.
///
/// The UI and the translation coordinator depend only on this interface, so a
/// new provider can be added without touching the book pipeline.
abstract interface class TranslationEngine {
  String get id;

  String get displayName;

  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  });

  void close();
}

class TranslationException implements Exception {
  const TranslationException(this.message, {this.code, this.retryable = false});

  final String message;
  final String? code;
  final bool retryable;

  @override
  String toString() => message;
}

class TranslationCancelledException implements Exception {
  const TranslationCancelledException();

  @override
  String toString() => '翻译已取消';
}
