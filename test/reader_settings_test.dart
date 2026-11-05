import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation_app/models/reader_settings.dart';
import 'package:translation_app/state/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reader preferences serialize every field', () {
    const preferences = ReaderPreferences(
      fontSize: 21,
      lineHeight: 2.1,
      skin: ReaderSkin.sepia,
      typeface: ReaderTypeface.sans,
      volumeKeysTurnPages: true,
      mode: ReaderMode.page,
      fontWeight: ReaderFontWeight.medium,
      paragraphSpacing: 18,
      firstLineIndent: 1,
      horizontalMargin: 30,
      topMargin: 24,
      bottomMargin: 36,
      keepScreenOn: true,
      hideStatusBar: false,
      tapToTurnPage: false,
      turnAnimation: ReaderTurnAnimation.none,
      showClock: false,
      showChapterTitle: false,
      showProgress: false,
      showPageNumber: false,
      justify: false,
    );

    final restored = ReaderPreferences.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(preferences.toJson())) as Map,
      ),
    );

    expect(restored, preferences);
    expect(restored.layoutSignature, preferences.layoutSignature);
  });

  test('invalid values are normalized instead of breaking the reader', () {
    final normalized = ReaderPreferences.fromJson({
      'fontSize': 99,
      'lineHeight': -1,
      'skin': 'unknown',
      'mode': 'unknown',
      'fontWeight': 'unknown',
      'paragraphSpacing': 200,
      'firstLineIndent': -3,
      'horizontalMargin': 400,
      'topMargin': 0,
      'bottomMargin': 999,
      'turnAnimation': 'unknown',
    });

    expect(normalized.fontSize, ReaderPreferences.maxFontSize);
    expect(normalized.lineHeight, ReaderPreferences.minLineHeight);
    expect(normalized.skin, ReaderSkin.night);
    expect(normalized.mode, ReaderMode.scroll);
    expect(normalized.fontWeight, ReaderFontWeight.regular);
    expect(normalized.paragraphSpacing, ReaderPreferences.maxParagraphSpacing);
    expect(normalized.firstLineIndent, ReaderPreferences.minFirstLineIndent);
    expect(normalized.horizontalMargin, ReaderPreferences.maxHorizontalMargin);
    expect(normalized.topMargin, ReaderPreferences.minVerticalMargin);
    expect(normalized.bottomMargin, ReaderPreferences.maxVerticalMargin);
    expect(normalized.turnAnimation, ReaderTurnAnimation.slide);
  });

  test(
    'settings controller persists and restores reader preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final first = SettingsController(preferences: preferences);
      await first.load();
      await first.setReaderPreferences(
        const ReaderPreferences(
          fontSize: 23,
          skin: ReaderSkin.paper,
          mode: ReaderMode.page,
          paragraphSpacing: 20,
          keepScreenOn: true,
          showClock: false,
        ),
      );

      final second = SettingsController(preferences: preferences);
      await second.load();
      expect(second.readerPreferences.fontSize, 23);
      expect(second.readerPreferences.skin, ReaderSkin.paper);
      expect(second.readerPreferences.mode, ReaderMode.page);
      expect(second.readerPreferences.paragraphSpacing, 20);
      expect(second.readerPreferences.keepScreenOn, isTrue);
      expect(second.readerPreferences.showClock, isFalse);

      await second.resetReaderPreferences();
      expect(second.readerPreferences, const ReaderPreferences());
    },
  );

  test('legacy v1.2 reader keys migrate into the new shape', () async {
    SharedPreferences.setMockInitialValues({
      'reader.font_size': 20.0,
      'reader.line_height': 2.2,
      'reader.skin': 'sepia',
      'reader.serif': false,
    });
    final preferences = await SharedPreferences.getInstance();
    final controller = SettingsController(preferences: preferences);
    await controller.load();

    expect(controller.readerPreferences.fontSize, 20);
    expect(controller.readerPreferences.lineHeight, 2.2);
    expect(controller.readerPreferences.skin, ReaderSkin.sepia);
    expect(controller.readerPreferences.serif, isFalse);
    expect(controller.readerPreferences.typeface, ReaderTypeface.sans);
    expect(controller.readerPreferences.volumeKeysTurnPages, isFalse);
    expect(controller.readerPreferences.mode, ReaderMode.scroll);
  });
}
