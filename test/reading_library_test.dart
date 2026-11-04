import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/bookmark.dart';
import 'package:translation_app/services/local_store.dart';
import 'package:translation_app/state/library_controller.dart';

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_library',
      title: '阅读控制器测试',
      author: '未知作者',
      fileName: '阅读控制器测试.txt',
      format: BookFormat.txt,
      chapterCount: 3,
      charCount: 90,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(id: 'c0', index: 0, title: '第一章', text: '一'),
      BookChapter(id: 'c1', index: 1, title: '第二章', text: '二'),
      BookChapter(id: 'c2', index: 2, title: '第三章', text: '三'),
    ],
  );
}

void main() {
  late Directory root;
  late LocalStore store;
  late LibraryController library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reading_library_');
    store = LocalStore(root);
    await store.ensureReady();
    await store.saveBook(_book());
    await store.saveLibrary([_book().meta]);
    library = LibraryController(store: store);
    await library.load();
  });

  tearDown(() async {
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows may keep a handle briefly.
    }
  });

  test('saves in-chapter progress and accumulates reading time', () async {
    await library.saveProgress(
      'book_library',
      1,
      chapterFraction: 0.25,
      addReadingSeconds: 120,
    );

    final first = library.progressFor('book_library')!;
    expect(first.chapterIndex, 1);
    expect(first.chapterFraction, 0.25);
    expect(first.readingSeconds, 120);
    expect(first.fraction, closeTo(1.25 / 3, 0.0001));

    await library.saveProgress(
      'book_library',
      1,
      chapterFraction: 0.5,
      addReadingSeconds: 60,
    );
    final second = library.progressFor('book_library')!;
    expect(second.chapterFraction, 0.5);
    expect(second.readingSeconds, 180);

    final reloaded = LibraryController(store: store);
    await reloaded.load();
    final persisted = reloaded.progressFor('book_library')!;
    expect(persisted.chapterFraction, 0.5);
    expect(persisted.readingSeconds, 180);
  });

  test('adds, finds and removes bookmarks and reloads them', () async {
    final bookmark = Bookmark.create(
      bookId: 'book_library',
      chapterIndex: 0,
      chapterTitle: '第一章',
      fraction: 0.2,
      snippet: '开头的一段话',
    );
    await library.addBookmark(bookmark);

    expect(library.bookmarkCount, 1);
    expect(library.bookmarksFor('book_library'), hasLength(1));
    expect(library.bookmarkNear('book_library', 0, 0.21)?.id, bookmark.id);
    expect(library.bookmarkNear('book_library', 1, 0.2), isNull);

    final reloaded = LibraryController(store: store);
    await reloaded.load();
    expect(reloaded.bookmarksFor('book_library'), hasLength(1));
    expect(reloaded.bookmarksFor('book_library').first.snippet, '开头的一段话');

    await library.removeBookmark(bookmark.id);
    expect(library.bookmarksFor('book_library'), isEmpty);
  });

  test('deleting a book also clears its progress and bookmarks', () async {
    await library.saveProgress('book_library', 1, chapterFraction: 0.4);
    await library.addBookmark(
      Bookmark.create(
        bookId: 'book_library',
        chapterIndex: 1,
        chapterTitle: '第二章',
        fraction: 0.4,
        snippet: '书签内容',
      ),
    );

    await library.deleteBook('book_library');
    expect(library.progressFor('book_library'), isNull);
    expect(library.bookmarksFor('book_library'), isEmpty);

    final reloaded = LibraryController(store: store);
    await reloaded.load();
    expect(reloaded.progressFor('book_library'), isNull);
    expect(reloaded.bookmarksFor('book_library'), isEmpty);
  });
}
