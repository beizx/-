import 'package:flutter/foundation.dart';
import 'dart:io';

import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/reading_progress.dart';
import '../services/import/book_importer.dart';
import '../services/local_store.dart';

/// Owns the local library: import, open, delete, reading positions and
/// bookmarks.
class LibraryController extends ChangeNotifier {
  LibraryController({required this.store, BookImporter? importer})
    : _importer = importer ?? BookImporter();

  final LocalStore store;
  final BookImporter _importer;

  final List<BookMeta> _books = [];
  final Map<String, Book> _bookCache = {};
  final List<Bookmark> _bookmarks = [];
  Set<String> _translatedLanguages = {};
  Map<String, ReadingProgress> _readingProgress = {};
  bool _isLoading = true;
  bool _isImporting = false;
  String? _loadError;

  List<BookMeta> get books => List.unmodifiable(_books);
  Set<String> get translatedLanguages => Set.unmodifiable(_translatedLanguages);
  Map<String, ReadingProgress> get readingProgress =>
      Map.unmodifiable(_readingProgress);
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);
  int get bookmarkCount => _bookmarks.length;

  ReadingProgress? progressFor(String bookId) => _readingProgress[bookId];

  List<Bookmark> bookmarksFor(String bookId) {
    final result =
        _bookmarks.where((bookmark) => bookmark.bookId == bookId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// A bookmark is considered "here" when it is in the same chapter and within
  /// roughly one page of the current position.
  Bookmark? bookmarkNear(
    String bookId,
    int chapterIndex,
    double fraction, {
    double tolerance = 0.04,
  }) {
    for (final bookmark in _bookmarks) {
      if (bookmark.bookId != bookId) continue;
      if (bookmark.chapterIndex != chapterIndex) continue;
      if ((bookmark.fraction - fraction).abs() <= tolerance) return bookmark;
    }
    return null;
  }

  Future<void> saveProgress(
    String bookId,
    int chapterIndex, {
    double chapterFraction = 0,
    int addReadingSeconds = 0,
  }) async {
    final chapterCount =
        _books.where((book) => book.id == bookId).firstOrNull?.chapterCount ??
        0;
    if (chapterCount <= 0) return;
    final existing = _readingProgress[bookId];
    final seconds =
        (existing?.readingSeconds ?? 0) +
        (addReadingSeconds > 0 ? addReadingSeconds : 0);
    _readingProgress = {
      ..._readingProgress,
      bookId: ReadingProgress(
        bookId: bookId,
        chapterIndex: chapterIndex.clamp(0, chapterCount - 1),
        chapterCount: chapterCount,
        chapterFraction: chapterFraction.clamp(0.0, 1.0),
        readingSeconds: seconds,
        updatedAt: DateTime.now(),
      ),
    };
    await store.saveReadingProgress(_readingProgress);
    notifyListeners();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    _bookmarks.removeWhere((item) => item.id == bookmark.id);
    _bookmarks.add(bookmark);
    await store.saveBookmarks(_bookmarks);
    notifyListeners();
  }

  Future<void> removeBookmark(String bookmarkId) async {
    _bookmarks.removeWhere((item) => item.id == bookmarkId);
    await store.saveBookmarks(_bookmarks);
    notifyListeners();
  }

  int get bookCount => _books.length;
  int get translatedLanguageCount => _translatedLanguages.length;
  bool get isLoading => _isLoading;
  bool get isImporting => _isImporting;
  String? get loadError => _loadError;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      await store.ensureReady();
      final loaded = await store.loadLibrary();
      _books
        ..clear()
        ..addAll(loaded);
      _translatedLanguages = await store.translatedLanguages();
      _readingProgress = await store.loadReadingProgress();
      _bookmarks
        ..clear()
        ..addAll(await store.loadBookmarks());
    } on Object catch (error) {
      _loadError = '书库加载失败：$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Opens the picker. Returns `null` if the user cancels.
  Future<Book?> importBook() async {
    if (_isImporting) return null;
    _isImporting = true;
    notifyListeners();
    try {
      final book = await _importer.pickAndImport();
      if (book == null) return null;
      await _register(book);
      return book;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  /// Imports a file that another app opened with us (QQ, Files, 分享面板).
  Future<Book?> importFromPath({
    required String path,
    required String fileName,
  }) async {
    if (_isImporting) return null;
    _isImporting = true;
    notifyListeners();
    try {
      final file = File(path);
      final length = await file.length();
      if (length > BookImporter.maxFileBytes) {
        throw const BookImportException('文件超过 80 MB，请先拆分后再导入');
      }
      final bytes = await file.readAsBytes();
      final book = await _importer.importBytes(
        bytes: bytes,
        fileName: fileName,
      );
      await _register(book);
      return book;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  /// Persists a freshly parsed book and puts it on top of the shelf.
  Future<void> _register(Book book) async {
    await store.saveBook(book);
    _bookCache[book.id] = book;
    _books.removeWhere((item) => item.id == book.id);
    _books.insert(0, book.meta);
    await store.saveLibrary(_books);
    _translatedLanguages = await store.translatedLanguages();
    notifyListeners();
  }

  Future<Book?> openBook(String bookId) async {
    final cached = _bookCache[bookId];
    if (cached != null) return cached;
    final loaded = await store.loadBook(bookId);
    if (loaded != null) _bookCache[bookId] = loaded;
    return loaded;
  }

  /// Adds a locally generated book (for example a deduplicated copy).
  Future<void> addBook(Book book) async {
    await store.saveBook(book);
    _bookCache[book.id] = book;
    _books.removeWhere((item) => item.id == book.id);
    _books.insert(0, book.meta);
    await store.saveLibrary(_books);
    notifyListeners();
  }

  Future<void> deleteBook(String bookId) async {
    _books.removeWhere((book) => book.id == bookId);
    _bookCache.remove(bookId);
    _readingProgress.remove(bookId);
    _bookmarks.removeWhere((bookmark) => bookmark.bookId == bookId);
    await store.saveReadingProgress(_readingProgress);
    await store.saveBookmarks(_bookmarks);
    await store.deleteBook(bookId);
    await store.saveLibrary(_books);
    _translatedLanguages = await store.translatedLanguages();
    notifyListeners();
  }

  Future<void> refreshTranslatedLanguages() async {
    _translatedLanguages = await store.translatedLanguages();
    notifyListeners();
  }
}
