import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/language.dart';

void main() {
  test('language registry exposes four targets and an auto source', () {
    expect(Languages.all.length, 5);
    expect(Languages.targetOptions.length, 4);
    expect(Languages.targetOptions.any((language) => language.isAuto), isFalse);
    expect(Languages.sourceOptions.first.isAuto, isTrue);
  });

  test('unknown persisted codes fall back safely', () {
    expect(Languages.sourceByCode('not-a-language').code, 'auto');
    expect(Languages.byCode('not-a-language').code, 'zh');
    expect(Languages.byCode(null, fallback: Languages.en).code, 'en');
  });

  test('provider codes are isolated from UI codes', () {
    expect(Languages.zh.providerCode('youdao'), 'zh-CHS');
    expect(Languages.ja.providerCode('youdao'), 'ja');
    expect(Languages.ko.providerCode('youdao'), 'ko');
    expect(Languages.en.providerCode('youdao'), 'en');
    expect(Languages.auto.providerCode('youdao'), 'auto');
  });
}
