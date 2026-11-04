import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:translation_app/services/translation/translation_engine.dart';
import 'package:translation_app/services/translation/youdao_engine.dart';

void main() {
  group('YoudaoSignature', () {
    test('truncates queries longer than 20 characters', () {
      const query =
          '你好，世界！This is a long query used for signature verification.';
      final truncated = YoudaoSignature.truncateQuery(query);
      expect(truncated, contains('59'));
      expect(truncated.startsWith('你好，世界！This'), isTrue);
      expect(truncated.endsWith('ification.'), isTrue);
    });

    test('matches the API v3 reference vector', () {
      const query =
          '你好，世界！This is a long query used for signature verification.';
      final sign = YoudaoSignature.sign(
        appKey: 'test-app-key',
        query: query,
        salt: '1700000000000000',
        curtime: '1700000000',
        appSecret: 'test-secret',
      );
      expect(
        sign,
        '3f3cea93e2c9cc325ab6b0edee60f508aa426d3edff94717eb5447b91403a205',
      );
    });
  });

  group('YoudaoEngine', () {
    test('posts a v3-signed request and returns the translated text', () async {
      late Map<String, String> sentFields;
      final client = MockClient((request) async {
        expect(request.url, YoudaoEngine.endpoint);
        expect(request.method, 'POST');
        sentFields = Uri.splitQueryString(request.body);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'errorCode': '0',
              'translation': ['你好，世界'],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final engine = YoudaoEngine(
        appKey: 'test-app-key',
        appSecret: 'test-secret',
        client: client,
      );

      final result = await engine.translate(
        text: 'Hello world',
        sourceLanguage: 'auto',
        targetLanguage: 'zh',
      );

      expect(result, '你好，世界');
      expect(sentFields['q'], 'Hello world');
      expect(sentFields['from'], 'auto');
      expect(sentFields['to'], 'zh-CHS');
      expect(sentFields['appKey'], 'test-app-key');
      expect(sentFields['signType'], 'v3');
      expect(sentFields['salt'], isNotEmpty);
      expect(sentFields['curtime'], isNotEmpty);
      expect(
        sentFields['sign'],
        YoudaoSignature.sign(
          appKey: 'test-app-key',
          query: 'Hello world',
          salt: sentFields['salt']!,
          curtime: sentFields['curtime']!,
          appSecret: 'test-secret',
        ),
      );
      engine.close();
    });

    test('maps signature errors to a readable message', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'errorCode': '202'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final engine = YoudaoEngine(
        appKey: 'bad',
        appSecret: 'bad',
        client: client,
      );

      await expectLater(
        engine.translate(
          text: 'Hello',
          sourceLanguage: 'auto',
          targetLanguage: 'zh',
        ),
        throwsA(
          isA<TranslationException>()
              .having((error) => error.code, 'code', '202')
              .having((error) => error.message, 'message', contains('签名校验失败'))
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
      engine.close();
    });

    test('marks rate-limit errors as retryable', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'errorCode': '206'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final engine = YoudaoEngine(
        appKey: 'key',
        appSecret: 'secret',
        client: client,
      );

      await expectLater(
        engine.translate(
          text: 'Hello',
          sourceLanguage: 'auto',
          targetLanguage: 'zh',
        ),
        throwsA(
          isA<TranslationException>().having(
            (error) => error.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
      engine.close();
    });
  });
}
