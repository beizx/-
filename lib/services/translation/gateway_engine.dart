import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/language.dart';
import 'translation_engine.dart';

/// Talks to the self-hosted Go gateway (`server/` in this repository) instead
/// of calling a provider directly.
///
/// The gateway owns the Youdao signing keys, so the phone only needs a URL and
/// an optional shared token. That keeps provider secrets off user devices and
/// lets one deployment serve many clients.
class GatewayEngine implements TranslationEngine {
  GatewayEngine({
    required String baseUrl,
    String? token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : baseUrl = _normalizeBaseUrl(baseUrl),
       token = (token ?? '').trim(),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String baseUrl;
  final String token;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get id => 'gateway';

  @override
  String get displayName => '自建 Go 网关';

  static String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Uri get endpoint => Uri.parse('$baseUrl/v1/translate');

  /// Health probe used by the settings page.
  Future<String> ping() async {
    final uri = Uri.parse('$baseUrl/healthz');
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw TranslationException('网关返回 HTTP ${response.statusCode}');
      }
      return '网关在线';
    } on TimeoutException {
      throw const TranslationException('连接网关超时，请检查地址与网络');
    } on TranslationException {
      rethrow;
    } on Object catch (error) {
      throw TranslationException('无法连接网关：$error');
    }
  }

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final query = text.trim();
    if (query.isEmpty) {
      throw const TranslationException('待翻译文本为空');
    }
    if (baseUrl.isEmpty) {
      throw const TranslationException('请先在设置中填写网关地址', code: 'config');
    }

    final source = Languages.sourceByCode(sourceLanguage);
    final target = Languages.byCode(targetLanguage);
    if (target.isAuto) {
      throw const TranslationException('目标语言不能是自动识别', code: 'config');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    late http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: headers,
            body: jsonEncode({
              'text': query,
              // The Go gateway forwards to Youdao v3, so it expects Youdao
              // language codes (`zh-CHS`, `en`, `ja`, `ko`, `auto`).
              'from': source.providerCode('youdao'),
              'to': target.providerCode('youdao'),
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const TranslationException(
        '网关响应超时，请稍后重试',
        code: 'timeout',
        retryable: true,
      );
    } on Object {
      throw const TranslationException(
        '无法连接自建网关，请检查地址与网络',
        code: 'network',
        retryable: true,
      );
    }

    if (response.statusCode != 200) {
      final message = _errorMessage(response);
      throw TranslationException(
        message,
        code: 'http_${response.statusCode}',
        retryable: response.statusCode == 429 || response.statusCode >= 500,
      );
    }

    final Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('response is not a JSON object');
      }
      payload = Map<String, Object?>.from(decoded);
    } on Object {
      throw const TranslationException(
        '网关返回了无法解析的数据',
        code: 'invalid_response',
        retryable: true,
      );
    }

    final translated = payload['text']?.toString().trim() ?? '';
    if (translated.isEmpty) {
      throw const TranslationException(
        '网关没有返回译文，请稍后重试',
        code: 'empty_translation',
        retryable: true,
      );
    }
    return translated;
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final error = decoded['error']?.toString();
        if (error != null && error.trim().isNotEmpty) return error;
      }
    } on Object {
      // Fall through to the generic message.
    }
    return '网关返回 HTTP ${response.statusCode}，请稍后重试';
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
