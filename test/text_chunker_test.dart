import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/services/translation/text_chunker.dart';

void main() {
  group('TextChunker', () {
    test('keeps short text in one chunk', () {
      final chunks = TextChunker.chunk('第一段。\n\n第二段。');
      expect(chunks, hasLength(1));
      expect(chunks.first, '第一段。\n\n第二段。');
    });

    test('never exceeds the requested size', () {
      final text = List.generate(
        40,
        (index) => '这是第 $index 段文字，' * 30,
      ).join('\n\n');
      const maxChars = 300;
      final chunks = TextChunker.chunk(text, maxChars: maxChars);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.runes.length, lessThanOrEqualTo(maxChars));
      }
    });

    test('splits an oversized paragraph at sentence punctuation', () {
      final sentence = '海风吹过甲板，他抬头看见远处的灯。';
      final text = List.filled(160, sentence).join();
      final chunks = TextChunker.chunk(text, maxChars: 240);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.runes.length, lessThanOrEqualTo(240));
        expect(chunk.endsWith('。'), isTrue);
      }
    });

    test('drops blank paragraphs and preserves every source segment', () {
      final text = 'Alpha paragraph.\n\n\n\nBeta paragraph.\n\nGamma.';
      final chunks = TextChunker.chunk(text);
      final combined = chunks.join('\n\n');
      expect(combined, contains('Alpha paragraph.'));
      expect(combined, contains('Beta paragraph.'));
      expect(combined, contains('Gamma.'));
      expect(combined, isNot(contains('\n\n\n')));
    });

    test('rejects too-small chunk sizes', () {
      expect(
        () => TextChunker.chunk('hello', maxChars: 10),
        throwsArgumentError,
      );
    });
  });
}
