import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/services/translation/book_translator.dart';
import 'package:translation_app/services/translation/translation_engine.dart';

class FakeEngine implements TranslationEngine {
  FakeEngine({this.failuresBeforeSuccess = 0});

  final int failuresBeforeSuccess;
  int calls = 0;
  bool closed = false;

  @override
  String get id => 'fake';

  @override
  String get displayName => '测试引擎';

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    calls++;
    if (calls <= failuresBeforeSuccess) {
      throw const TranslationException(
        'rate limited',
        code: '206',
        retryable: true,
      );
    }
    return '译：$text';
  }

  @override
  void close() {
    closed = true;
  }
}

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_translate',
      title: '测试书',
      author: '未知作者',
      fileName: '测试书.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 20,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(id: 'chapter_0', index: 0, title: '第一章', text: '第一段文字。'),
      BookChapter(id: 'chapter_1', index: 1, title: '第二章', text: '第二段文字。'),
    ],
  );
}

void main() {
  group('BookTranslator', () {
    test('translates every chapter and reports complete progress', () async {
      final engine = FakeEngine();
      final progress = <TranslationProgress>[];
      final record = await const BookTranslator().translate(
        book: _book(),
        engine: engine,
        sourceLanguage: Languages.zh,
        targetLanguage: Languages.ja,
        onProgress: progress.add,
        isCancelled: () => false,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      expect(record.chapters, hasLength(2));
      expect(record.chapters.first.text, contains('译：第一段文字。'));
      expect(record.targetLanguage, 'ja');
      expect(record.providerId, 'fake');
      expect(progress, isNotEmpty);
      expect(progress.last.fraction, 1);
      expect(progress.last.completedChunks, progress.last.totalChunks);
    });

    test('retries retryable engine failures', () async {
      final engine = FakeEngine(failuresBeforeSuccess: 2);
      final record = await const BookTranslator().translate(
        book: _book(),
        engine: engine,
        sourceLanguage: Languages.en,
        targetLanguage: Languages.zh,
        onProgress: (_) {},
        isCancelled: () => false,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      expect(engine.calls, 4);
      expect(record.chapters.first.text, isNotEmpty);
    });

    test('throws when cancelled before the first request', () async {
      final engine = FakeEngine();
      await expectLater(
        const BookTranslator().translate(
          book: _book(),
          engine: engine,
          sourceLanguage: Languages.auto,
          targetLanguage: Languages.ko,
          onProgress: (_) {},
          isCancelled: () => true,
          requestInterval: Duration.zero,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<TranslationCancelledException>()),
      );
      expect(engine.calls, 0);
    });

    test('surfaces non-retryable failures', () async {
      final engine = _FailingEngine();
      await expectLater(
        const BookTranslator().translate(
          book: _book(),
          engine: engine,
          sourceLanguage: Languages.zh,
          targetLanguage: Languages.en,
          onProgress: (_) {},
          isCancelled: () => false,
          requestInterval: Duration.zero,
          retryDelay: Duration.zero,
        ),
        throwsA(
          isA<TranslationException>().having(
            (error) => error.code,
            'code',
            '202',
          ),
        ),
      );
      expect(engine.calls, 1);
    });
  });
}

class _FailingEngine implements TranslationEngine {
  int calls = 0;

  @override
  String get id => 'failing';

  @override
  String get displayName => '失败引擎';

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    calls++;
    throw const TranslationException('bad signature', code: '202');
  }

  @override
  void close() {}
}
