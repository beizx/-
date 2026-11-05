import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/models/reading_progress.dart';
import 'package:translation_app/models/translation_draft.dart';
import 'package:translation_app/services/local_store.dart';

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_store',
      title: '存储测试',
      author: '未知作者',
      fileName: '存储测试.txt',
      format: BookFormat.txt,
      chapterCount: 1,
      charCount: 4,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(id: 'chapter_0', index: 0, title: '全文', text: '海风吹过。'),
    ],
  );
}

TranslationRecord _record() {
  return TranslationRecord(
    bookId: 'book_store',
    sourceLanguage: 'zh',
    targetLanguage: Languages.en.code,
    providerId: 'youdao',
    createdAt: DateTime(2026, 11, 4),
    chapters: const [
      TranslatedChapter(
        chapterId: 'chapter_0',
        chapterIndex: 0,
        title: '全文',
        text: 'The sea breeze passed by.',
      ),
    ],
  );
}

void main() {
  late Directory root;
  late LocalStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('translation_store_');
    store = LocalStore(root);
    await store.ensureReady();
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('persists library, books and translations', () async {
    final book = _book();
    await store.saveBook(book);
    await store.saveLibrary([book.meta]);
    await store.saveTranslation(_record());

    final library = await store.loadLibrary();
    expect(library, hasLength(1));
    expect(library.first.title, '存储测试');

    final loadedBook = await store.loadBook('book_store');
    expect(loadedBook, isNotNull);
    expect(loadedBook!.chapters.first.text, '海风吹过。');

    final loadedTranslation = await store.loadTranslation('book_store', 'en');
    expect(loadedTranslation, isNotNull);
    expect(loadedTranslation!.chapters.first.text, 'The sea breeze passed by.');

    final languages = await store.translatedLanguages();
    expect(languages, contains('en'));
  });

  test('persists reading progress and removes it with the book', () async {
    await store.saveBook(_book());
    await store.saveLibrary([_book().meta]);
    final progress = ReadingProgress(
      bookId: 'book_store',
      chapterIndex: 0,
      chapterCount: 1,
      updatedAt: DateTime(2026, 11, 4, 10),
    );
    await store.saveReadingProgress({'book_store': progress});

    final loaded = await store.loadReadingProgress();
    expect(loaded['book_store']?.chapterIndex, 0);

    await store.deleteBook('book_store');
    await store.saveReadingProgress({});
    expect(await store.loadReadingProgress(), isEmpty);
  });

  test('deleting a book also removes its translations', () async {
    await store.saveBook(_book());
    await store.saveLibrary([_book().meta]);
    await store.saveTranslation(_record());

    await store.deleteBook('book_store');

    expect(await store.loadBook('book_store'), isNull);
    expect(await store.loadTranslation('book_store', 'en'), isNull);
    expect(await store.translatedLanguages(), isEmpty);
  });

  test(
    'persists a translation draft without counting it as a language',
    () async {
      final draft = TranslationDraft(
        bookId: 'book_store',
        sourceLanguage: 'zh',
        targetLanguage: 'en',
        providerId: 'youdao',
        updatedAt: DateTime(2026, 11, 5, 8),
        totalChunks: 4,
        chunks: const {'chapter_0#0': SavedChunk(hash: 'abc', text: 'partial')},
        failedKeys: const ['chapter_0#1'],
      );
      await store.saveDraft(draft);
      await store.saveTranslation(_record());

      final loaded = await store.loadDraft('book_store', 'en');
      expect(loaded, isNotNull);
      expect(loaded!.succeeded, 1);
      expect(loaded.failedChunks, 1);
      expect(loaded.chunks['chapter_0#0']?.text, 'partial');
      expect(await store.translatedLanguages(), {'en'});

      await store.deleteBook('book_store');
      expect(await store.loadDraft('book_store', 'en'), isNull);
      expect(await store.loadTranslation('book_store', 'en'), isNull);
    },
  );

  test('keeps unknown or corrupt entries out of the library', () async {
    await File(p.join(root.path, 'library.json')).writeAsString('[{}]');
    expect(await store.loadLibrary(), isEmpty);

    await File(p.join(root.path, 'library.json')).writeAsString('not-json');
    expect(await store.loadLibrary(), isEmpty);
  });
}
