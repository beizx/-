import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/services/import/txt_parser.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('TxtParser', () {
    test('parses UTF-8 with BOM and splits Chinese chapters', () {
      final text = '''
第一章 夜航
风从舷窗掠过。

第二章 灯火
他把灯点亮。
''';
      final withBom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(text),
      ]);
      final book = TxtParser.parse(bytes: withBom, fileName: '夜航.txt');

      expect(book.title, '夜航');
      expect(book.author, '未知作者');
      expect(book.meta.format.name, 'txt');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, '第一章 夜航');
      expect(book.chapters[0].text, contains('风从舷窗掠过。'));
      expect(book.chapters[0].text, isNot(contains('第一章')));
      expect(book.chapters[1].title, '第二章 灯火');
      expect(book.meta.chapterCount, 2);
      expect(book.meta.charCount, greaterThan(0));
    });

    test('decodes GBK TXT files', () {
      const source = '第一章 风起\n他来了。\n第二章 云涌\n她走了。';
      final gbkBytes = Uint8List.fromList(const GbkCodec().encode(source));
      final book = TxtParser.parse(bytes: gbkBytes, fileName: '风云.txt');

      expect(book.chapters, hasLength(2));
      expect(book.chapters.first.text, '他来了。');
      expect(book.chapters.last.text, '她走了。');
    });

    test('uses a leading book-title line as metadata', () {
      const text = '''《长夜灯塔》

第一章 起雾
海面起了雾。

第二章 归航
灯塔仍然亮着。
''';
      final book = TxtParser.parse(
        bytes: _bytes(text),
        fileName: 'download.txt',
      );

      expect(book.title, '长夜灯塔');
      expect(book.chapters, hasLength(2));
      expect(book.chapters.first.title, '第一章 起雾');
      expect(book.chapters.first.text, isNot(contains('长夜灯塔')));
    });

    test('auto-splits a long file without headings', () {
      final longParagraph = List.filled(400, '长').join();
      final lines = List.generate(20, (index) => '第 $index 行：$longParagraph');
      final book = TxtParser.parse(
        bytes: _bytes(lines.join('\n')),
        fileName: '无章节.txt',
      );

      expect(book.chapters.length, greaterThan(1));
      expect(book.title, '无章节');
      for (final chapter in book.chapters) {
        expect(chapter.title, startsWith('第 '));
        expect(chapter.text, isNotEmpty);
      }
    });

    test('recognises Chinese, English, Japanese and Korean headings', () {
      for (final heading in [
        '第一章 初见',
        '第十二回 风波',
        'Chapter 7 The Door',
        'PROLOGUE',
        '第3話 再会',
        '제 12 장 귀환',
        '番外 春日',
      ]) {
        expect(TxtParser.isChapterHeading(heading), isTrue, reason: heading);
      }

      for (final line in [
        '他推开门，看见了海。',
        '第二章的内容从这里开始。',
        'Chapter is not a heading by itself.',
        '这是一个很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长的句子。',
      ]) {
        expect(TxtParser.isChapterHeading(line), isFalse, reason: line);
      }
    });

    test('rejects empty files', () {
      expect(
        () => TxtParser.parse(bytes: Uint8List(0), fileName: '空.txt'),
        throwsFormatException,
      );
    });
  });
}
