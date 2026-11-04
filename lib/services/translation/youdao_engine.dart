import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../models/language.dart';
import 'translation_engine.dart';

/// Youdao Zhiyun text translation API v3.
///
/// https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html
class YoudaoEngine implements TranslationEngine {
  YoudaoEngine({
    required this.appKey,
    required this.appSecret,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static final Uri endpoint = Uri.parse('https://openapi.youdao.com/api');

  final String appKey;
  final String appSecret;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get id => 'youdao';

  @override
  String get displayName => '网易有道智云';

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
    if (appKey.trim().isEmpty || appSecret.trim().isEmpty) {
      throw const TranslationException(
        '请先填写有道智云 App ID 与 App Secret',
        code: 'config',
      );
    }

    final source = Languages.sourceByCode(sourceLanguage);
    final target = Languages.byCode(targetLanguage);
    if (target.isAuto) {
      throw const TranslationException('目标语言不能是自动识别', code: 'config');
    }

    final now = DateTime.now();
    final salt = now.microsecondsSinceEpoch.toString();
    final curtime = (now.millisecondsSinceEpoch ~/ 1000).toString();
    final sign = YoudaoSignature.sign(
      appKey: appKey,
      query: query,
      salt: salt,
      curtime: curtime,
      appSecret: appSecret,
    );

    final body = {
      'q': query,
      'from': source.providerCode(id),
      'to': target.providerCode(id),
      'appKey': appKey,
      'salt': salt,
      'sign': sign,
      'signType': 'v3',
      'curtime': curtime,
    };

    late http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: const {
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=UTF-8',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const TranslationException(
        '请求有道接口超时，请检查网络后重试',
        code: 'timeout',
        retryable: true,
      );
    } on Object {
      throw const TranslationException(
        '无法连接有道翻译接口，请检查网络',
        code: 'network',
        retryable: true,
      );
    }

    if (response.statusCode != 200) {
      throw TranslationException(
        '有道接口返回 HTTP ${response.statusCode}，请稍后重试',
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
        '有道接口返回了无法解析的数据',
        code: 'invalid_response',
        retryable: true,
      );
    }

    final errorCode = payload['errorCode']?.toString() ?? '0';
    if (errorCode != '0') {
      throw TranslationException(
        YoudaoErrorMessages.messageFor(errorCode),
        code: errorCode,
        retryable: YoudaoErrorMessages.isRetryable(errorCode),
      );
    }

    final translated = payload['translation'];
    if (translated is! List || translated.isEmpty) {
      throw const TranslationException(
        '有道接口没有返回译文，请稍后重试',
        code: 'empty_translation',
        retryable: true,
      );
    }

    final result = translated
        .whereType<String>()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
    if (result.isEmpty) {
      throw const TranslationException(
        '有道接口返回了空译文，请稍后重试',
        code: 'empty_translation',
        retryable: true,
      );
    }
    return result;
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

abstract final class YoudaoSignature {
  /// API v3 rule: if q is longer than 20 characters, sign
  /// first 10 + character count + last 10.
  static String truncateQuery(String query) {
    final runes = query.runes.toList();
    if (runes.length <= 20) return query;
    final first = String.fromCharCodes(runes.take(10));
    final last = String.fromCharCodes(runes.skip(runes.length - 10));
    return '$first${runes.length}$last';
  }

  static String sign({
    required String appKey,
    required String query,
    required String salt,
    required String curtime,
    required String appSecret,
  }) {
    final input = '$appKey${truncateQuery(query)}$salt$curtime$appSecret';
    return sha256.convert(utf8.encode(input)).toString();
  }
}

abstract final class YoudaoErrorMessages {
  static String messageFor(String code) {
    return switch (code) {
      '101' => '有道接口缺少必填参数，请稍后重试',
      '102' => '有道接口不支持所选的语言组合',
      '103' => '翻译文本过长，请调小分段长度',
      '108' => '有道 App ID 无效，请检查应用 ID',
      '110' => '有道账号未开通文本翻译服务',
      '111' => '有道开发者账号无效',
      '113' => '待翻译文本为空',
      '202' => '有道签名校验失败，请检查 App Secret 是否填写正确',
      '203' => '当前 IP 不在有道应用的可访问白名单中',
      '205' => '请求时间戳过期，请检查设备系统时间',
      '206' => '有道翻译请求频率受限，请稍后重试',
      '207' => '有道翻译并发超出限制，请稍后重试',
      '301' => '有道辞典查询失败',
      '302' => '有道翻译查询失败',
      '303' => '有道服务暂时异常，请稍后重试',
      '401' => '有道账号余额不足',
      '411' => '有道访问频率受限，请稍后重试',
      '412' => '有道请求字数超限，请调小分段长度',
      _ => '有道翻译失败（错误码 $code）',
    };
  }

  static bool isRetryable(String code) {
    return const {'206', '207', '303', '411', '412'}.contains(code);
  }
}
