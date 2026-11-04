import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/services/dedupe/multilingual_dedupe_service.dart';

Book _book({
  String text = '''海は静かだった。
大海很安静。
彼女は窓の外を見ていた。
她望着窗外。''',
  String title = '星海',
}) {
  return Book(
    meta: BookMeta(
      id: 'book_dedupe_source',
      title: title,
      author: '示例作者',
      fileName: '星海.txt',
      format: BookFormat.txt,
      chapterCount: 1,
      charCount: text.length,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: [
      BookChapter(id: 'chapter_0', index: 0, title: '第一章 海边', text: text),
    ],
  );
}

void main() {
  group('MultilingualDedupeService language detection', () {
    test('detects the four supported scripts', () {
      expect(MultilingualDedupeService.detectLanguage('海は静かだった。')?.code, 'ja');
      expect(MultilingualDedupeService.detectLanguage('大海很安静。')?.code, 'zh');
      expect(
        MultilingualDedupeService.detectLanguage('The sea was quiet.')?.code,
        'en',
      );
      expect(MultilingualDedupeService.detectLanguage('바다는 조용했다.')?.code, 'ko');
    });

    test('returns null for punctuation or numbers only', () {
      expect(MultilingualDedupeService.detectLanguage('—— 123 ...'), isNull);
      expect(MultilingualDedupeService.detectLanguage(''), isNull);
    });
  });

  group('MultilingualDedupeService analyze', () {
    test('finds alternating Japanese/Chinese pairs', () {
      final analysis = MultilingualDedupeService.analyze(
        _book(),
        keepLanguage: Languages.zh,
      );

      expect(analysis.candidates, hasLength(2));
      expect(analysis.affectedChapterCount, 1);
      expect(analysis.scannedParagraphs, 4);
      expect(analysis.candidates.first.keepLanguage.code, 'zh');
      expect(analysis.candidates.first.removeLanguage.code, 'ja');
      expect(analysis.candidates.first.keepText, '大海很安静。');
      expect(analysis.candidates.first.removeText, '海は静かだった。');
      expect(analysis.removableCharacterCount, greaterThan(0));
    });

    test('keeps Japanese when that side is selected', () {
      final analysis = MultilingualDedupeService.analyze(
        _book(),
        keepLanguage: Languages.ja,
      );

      expect(analysis.candidates, hasLength(2));
      expect(analysis.candidates.first.keepLanguage.code, 'ja');
      expect(analysis.candidates.first.removeLanguage.code, 'zh');
      expect(analysis.candidates.first.keepText, '海は静かだった。');
    });

    test('returns no candidates when the chosen language is absent', () {
      final analysis = MultilingualDedupeService.analyze(
        _book(),
        keepLanguage: Languages.en,
      );
      expect(analysis.candidates, isEmpty);
    });

    test('never pairs two paragraphs of the same language', () {
      final analysis = MultilingualDedupeService.analyze(
        _book(text: '第一段中文。\n第二段中文。\n第三段中文。'),
        keepLanguage: Languages.zh,
      );
      expect(analysis.candidates, isEmpty);
    });

    test('does not reuse one paragraph in two candidate pairs', () {
      final analysis = MultilingualDedupeService.analyze(
        _book(
          text: '''大海很安静。
海は静かだった。
她望着窗外。''',
        ),
        keepLanguage: Languages.zh,
      );

      expect(analysis.candidates, hasLength(1));
      expect(analysis.candidates.single.removeLineIndex, 1);
    });

    test('rejects unsupported keep languages', () {
      expect(
        () => MultilingualDedupeService.analyze(
          _book(),
          keepLanguage: Languages.auto,
        ),
        throwsA(isA<DedupeException>()),
      );
    });
  });

  group('MultilingualDedupeService generation', () {
    test('generates a new book and leaves the source untouched', () {
      final source = _book();
      final before = source.chapters.first.text;
      final analysis = MultilingualDedupeService.analyze(
        source,
        keepLanguage: Languages.zh,
      );

      final generated = MultilingualDedupeService.generateDedupedBook(
        source: source,
        keepLanguage: Languages.zh,
        selected: analysis.candidates,
      );

      expect(generated.id, isNot(source.id));
      expect(generated.title, '星海（中文去重版）');
      expect(generated.chapters, hasLength(1));
      expect(generated.chapters.first.text, '大海很安静。\n她望着窗外。');
      expect(generated.chapters.first.text, isNot(contains('海は')));
      expect(source.chapters.first.text, before);
      expect(source.chapters.first.text, contains('海は'));
    });

    test('can remove only a selected subset', () {
      final source = _book();
      final analysis = MultilingualDedupeService.analyze(
        source,
        keepLanguage: Languages.zh,
      );

      final generated = MultilingualDedupeService.generateDedupedBook(
        source: source,
        keepLanguage: Languages.zh,
        selected: [analysis.candidates.first],
      );

      expect(generated.chapters.first.text, contains('她望着窗外。'));
      expect(generated.chapters.first.text, isNot(contains('海は静かだった。')));
      expect(generated.chapters.first.text, contains('彼女は窓の外を見ていた。'));
    });

    test('keeps Korean when Korean is the selected language', () {
      final source = _book(
        text: '''바다는 조용했다.
The sea was quiet.
바람이 차가웠다.
The wind was cold.''',
      );
      final analysis = MultilingualDedupeService.analyze(
        source,
        keepLanguage: Languages.ko,
      );
      expect(analysis.candidates, hasLength(2));

      final generated = MultilingualDedupeService.generateDedupedBook(
        source: source,
        keepLanguage: Languages.ko,
        selected: analysis.candidates,
      );
      expect(generated.chapters.first.text, '바다는 조용했다.\n바람이 차가웠다.');
      expect(generated.chapters.first.text, isNot(contains('The sea')));
    });

    test('rejects an empty selection', () {
      expect(
        () => MultilingualDedupeService.generateDedupedBook(
          source: _book(),
          keepLanguage: Languages.zh,
          selected: const [],
        ),
        throwsA(isA<DedupeException>()),
      );
    });
  });
}
