import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/models/translation_draft.dart';
import 'package:translation_app/services/translation/book_translator.dart';
import 'package:translation_app/services/translation/text_chunker.dart';
import 'package:translation_app/services/translation/translation_engine.dart';

class FakeEngine implements TranslationEngine {
  FakeEngine({this.failuresBeforeSuccess = 0});

  final int failuresBeforeSuccess;
  int calls = 0;
  bool closed = false;
  final List<String> translatedTexts = [];

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
    translatedTexts.add(text);
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
      final result = await const BookTranslator().translate(
        book: _book(),
        engine: engine,
        sourceLanguage: Languages.zh,
        targetLanguage: Languages.ja,
        onProgress: progress.add,
        isCancelled: () => false,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      final record = result.record;
      expect(record, isNotNull);
      expect(record!.chapters, hasLength(2));
      expect(record.chapters.first.text, contains('译：第一段文字。'));
      expect(record.complete, isTrue);
      expect(record.targetLanguage, 'ja');
      expect(record.providerId, 'fake');
      expect(progress, isNotEmpty);
      expect(progress.last.fraction, 1);
      expect(progress.last.completedChunks, progress.last.totalChunks);
      expect(progress.last.failedChunks, 0);
    });

    test('retries retryable engine failures', () async {
      final engine = FakeEngine(failuresBeforeSuccess: 2);
      final result = await const BookTranslator().translate(
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
      expect(result.record?.chapters.first.text, isNotEmpty);
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

    test('keeps successes when another chunk fails', () async {
      final engine = _SelectiveEngine(fail: (text) => text.contains('第二'));
      final progress = <TranslationProgress>[];
      final result = await const BookTranslator().translate(
        book: _book(),
        engine: engine,
        sourceLanguage: Languages.zh,
        targetLanguage: Languages.en,
        onProgress: progress.add,
        isCancelled: () => false,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      expect(result.record, isNull);
      expect(result.cancelled, isFalse);
      expect(result.draft.succeeded, 1);
      expect(result.draft.failedChunks, 1);
      expect(engine.calls, 2);
      final readable = recordFromDraft(book: _book(), draft: result.draft);
      expect(readable, isNotNull);
      expect(readable!.complete, isFalse);
      expect(readable.chapters, hasLength(1));
      expect(readable.chapters.single.text, contains('第一段文字'));
      expect(progress.last.failedChunks, 1);
      expect(progress.last.remainingChunks, 0);
    });

    test('resume skips chunks that already succeeded', () async {
      final book = _book();
      final source = TextChunker.chunk(book.chapters.first.text).single;
      final draft = TranslationDraft(
        bookId: book.id,
        sourceLanguage: 'zh',
        targetLanguage: 'ja',
        providerId: 'fake',
        updatedAt: DateTime(2026, 11, 5),
        totalChunks: 2,
        chunks: {
          TranslationDraft.keyFor(book.chapters.first.id, 0): SavedChunk(
            hash: TranslationDraft.fingerprint(source),
            text: '已有译文',
          ),
        },
        failedKeys: const [],
      );
      final engine = FakeEngine();
      final result = await const BookTranslator().translate(
        book: book,
        engine: engine,
        sourceLanguage: Languages.zh,
        targetLanguage: Languages.ja,
        resume: draft,
        onProgress: (_) {},
        isCancelled: () => false,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      expect(engine.calls, 1);
      expect(result.record, isNotNull);
      expect(result.record!.chapters.first.text, '已有译文');
      expect(result.record!.chapters.last.text, contains('第二段文字'));
    });

    test('retryFailuresOnly does not retranslate successes', () async {
      final book = _book();
      final first = TextChunker.chunk(book.chapters.first.text).single;
      final second = TextChunker.chunk(book.chapters.last.text).single;
      final failedKey = TranslationDraft.keyFor(book.chapters.last.id, 0);
      final draft = TranslationDraft(
        bookId: book.id,
        sourceLanguage: 'zh',
        targetLanguage: 'en',
        providerId: 'fake',
        updatedAt: DateTime(2026, 11, 5),
        totalChunks: 2,
        chunks: {
          TranslationDraft.keyFor(book.chapters.first.id, 0): SavedChunk(
            hash: TranslationDraft.fingerprint(first),
            text: '保留',
          ),
        },
        failedKeys: [failedKey],
      );
      final engine = FakeEngine();
      final result = await const BookTranslator().translate(
        book: book,
        engine: engine,
        sourceLanguage: Languages.zh,
        targetLanguage: Languages.en,
        resume: draft,
        retryFailuresOnly: true,
        onProgress: (_) {},
        isCancelled: () => false,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      expect(engine.calls, 1);
      expect(engine.translatedTexts, [second]);
      expect(result.record?.chapters.first.text, '保留');
      expect(result.draft.failedChunks, 0);
    });

    test('cancel keeps chunks that already succeeded', () async {
      var cancel = false;
      final engine = FakeEngine();
      final result = await const BookTranslator().translate(
        book: _book(),
        engine: engine,
        sourceLanguage: Languages.zh,
        targetLanguage: Languages.ja,
        onProgress: (progress) {
          if (progress.completedChunks >= 1) cancel = true;
        },
        isCancelled: () => cancel,
        requestInterval: Duration.zero,
        retryDelay: Duration.zero,
      );

      expect(result.cancelled, isTrue);
      expect(result.record, isNull);
      expect(result.draft.succeeded, 1);
      expect(engine.calls, 1);
      final readable = recordFromDraft(book: _book(), draft: result.draft);
      expect(readable?.chapters.single.title, '第一章');
    });

    test('formats a short remaining-time estimate', () {
      expect(formatTranslationEta(const Duration(seconds: 20)), '不到 1 分钟');
      expect(formatTranslationEta(const Duration(minutes: 3)), '3 分钟');
      expect(formatTranslationEta(const Duration(minutes: 90)), '1 小时 30 分钟');
    });
  });
}

class _SelectiveEngine implements TranslationEngine {
  _SelectiveEngine({required this.fail});

  final bool Function(String text) fail;
  int calls = 0;

  @override
  String get id => 'selective';

  @override
  String get displayName => '选择性失败';

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    calls++;
    if (fail(text)) {
      throw const TranslationException('bad signature', code: '202');
    }
    return '译：$text';
  }

  @override
  void close() {}
}
