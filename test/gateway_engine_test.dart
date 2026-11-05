import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/services/translation/gateway_engine.dart';
import 'package:translation_app/services/translation/translation_engine.dart';

GatewayEngine _engine(
  MockClient client, {
  String baseUrl = 'http://gateway.test:8080/',
  String? token,
}) {
  return GatewayEngine(baseUrl: baseUrl, token: token, client: client);
}

void main() {
  test('posts text with Youdao language codes and the bearer token', () async {
    late http.Request captured;
    final engine = _engine(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'text': '你好世界', 'detectedSource': 'en'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      token: 'secret-token',
    );

    final result = await engine.translate(
      text: '  hello world  ',
      sourceLanguage: Languages.auto.code,
      targetLanguage: Languages.zh.code,
    );

    expect(result, '你好世界');
    expect(captured.url.toString(), 'http://gateway.test:8080/v1/translate');
    expect(captured.headers['Authorization'], 'Bearer secret-token');
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['text'], 'hello world');
    expect(body['from'], 'auto');
    expect(body['to'], Languages.zh.providerCode('youdao'));
    engine.close();
  });

  test('omits the Authorization header when no token is configured', () async {
    late http.Request captured;
    final engine = _engine(
      MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'text': 'ok'}), 200);
      }),
    );
    await engine.translate(
      text: 'hi',
      sourceLanguage: Languages.en.code,
      targetLanguage: Languages.zh.code,
    );
    expect(captured.headers.containsKey('Authorization'), isFalse);
    engine.close();
  });

  test('surfaces the gateway error message and retryability', () async {
    final engine = _engine(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'error': '请求过于频繁，请稍后重试', 'code': '411'}),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await expectLater(
      engine.translate(
        text: 'hi',
        sourceLanguage: Languages.auto.code,
        targetLanguage: Languages.zh.code,
      ),
      throwsA(
        isA<TranslationException>()
            .having((error) => error.message, 'message', contains('频繁'))
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
    engine.close();
  });

  test('rejects empty text before touching the network', () async {
    final engine = _engine(
      MockClient((_) async => throw StateError('must not be called')),
    );
    await expectLater(
      engine.translate(
        text: '   ',
        sourceLanguage: Languages.auto.code,
        targetLanguage: Languages.zh.code,
      ),
      throwsA(isA<TranslationException>()),
    );
    engine.close();
  });

  test('requires a base url', () async {
    final engine = GatewayEngine(
      baseUrl: '  ',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      engine.translate(
        text: 'hi',
        sourceLanguage: Languages.auto.code,
        targetLanguage: Languages.zh.code,
      ),
      throwsA(
        isA<TranslationException>().having(
          (error) => error.message,
          'message',
          contains('网关地址'),
        ),
      ),
    );
    engine.close();
  });

  test('normalizes a bare host into an http url', () {
    final engine = GatewayEngine(
      baseUrl: '192.168.1.5:8080/',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(engine.endpoint.toString(), 'http://192.168.1.5:8080/v1/translate');
    engine.close();
  });

  test('ping reports a reachable gateway', () async {
    final engine = _engine(
      MockClient((request) async {
        expect(request.url.path, '/healthz');
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }),
    );
    expect(await engine.ping(), '网关在线');
    engine.close();
  });
}
