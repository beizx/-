import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/reading_progress.dart';

/// Owns the on-device workspace:
///
/// ```
/// translation_app/
///   library.json
///   progress.json
///   bookmarks.json
///   books/{bookId}.json
///   translations/{bookId}_{language}.json
///   exports/
/// ```
///
/// Only parsed text is written to disk. API keys never touch this store.
class LocalStore {
  LocalStore(this.root);

  final Directory root;

  /// Serializes writes per file. Progress and bookmarks can be saved from
  /// scroll callbacks, so concurrent temp-file renames must not collide.
  final Map<String, Future<void>> _pendingWrites = {};

  static Future<LocalStore> open() async {
    final support = await getApplicationSupportDirectory();
    final store = LocalStore(
      Directory(p.join(support.path, 'translation_app')),
    );
    await store.ensureReady();
    return store;
  }

  Directory get _booksDirectory => Directory(p.join(root.path, 'books'));
  Directory get _translationsDirectory =>
      Directory(p.join(root.path, 'translations'));
  Directory get exportsDirectory => Directory(p.join(root.path, 'exports'));
  File get _indexFile => File(p.join(root.path, 'library.json'));
  File get _progressFile => File(p.join(root.path, 'progress.json'));
  File get _bookmarksFile => File(p.join(root.path, 'bookmarks.json'));

  Future<void> ensureReady() async {
    await root.create(recursive: true);
    await _booksDirectory.create(recursive: true);
    await _translationsDirectory.create(recursive: true);
    await exportsDirectory.create(recursive: true);
  }

  Future<List<BookMeta>> loadLibrary() async {
    if (!await _indexFile.exists()) return [];
    try {
      final raw = await _indexFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final books = <BookMeta>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          books.add(BookMeta.fromJson(Map<String, Object?>.from(item)));
        } on Object {
          // Skip a single damaged entry instead of losing the whole library.
        }
      }
      books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      return books;
    } on Object {
      return [];
    }
  }

  Future<void> saveLibrary(List<BookMeta> books) async {
    await _writeJson(_indexFile, books.map((book) => book.toJson()).toList());
  }

  /// Reading positions keyed by book id, used by the shelf for resume.
  Future<Map<String, ReadingProgress>> loadReadingProgress() async {
    if (!await _progressFile.exists()) return {};
    try {
      final decoded = jsonDecode(await _progressFile.readAsString());
      if (decoded is! List) return {};
      final progress = <String, ReadingProgress>{};
      for (final item in decoded.whereType<Map>()) {
        try {
          final entry = ReadingProgress.fromJson(
            Map<String, Object?>.from(item),
          );
          if (entry.bookId.isNotEmpty) progress[entry.bookId] = entry;
        } on Object {
          // Skip a single damaged entry rather than losing all positions.
        }
      }
      return progress;
    } on Object {
      return {};
    }
  }

  Future<void> saveReadingProgress(
    Map<String, ReadingProgress> progress,
  ) async {
    await _writeJson(
      _progressFile,
      progress.values.map((entry) => entry.toJson()).toList(),
    );
  }

  /// Bookmarks for every book, kept in one small index file.
  Future<List<Bookmark>> loadBookmarks() async {
    if (!await _bookmarksFile.exists()) return [];
    try {
      final decoded = jsonDecode(await _bookmarksFile.readAsString());
      if (decoded is! List) return [];
      final bookmarks = <Bookmark>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          final bookmark = Bookmark.fromJson(Map<String, Object?>.from(item));
          if (bookmark.bookId.isNotEmpty) bookmarks.add(bookmark);
        } on Object {
          // Skip one damaged bookmark instead of losing the whole list.
        }
      }
      bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookmarks;
    } on Object {
      return [];
    }
  }

  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    await _writeJson(
      _bookmarksFile,
      bookmarks.map((bookmark) => bookmark.toJson()).toList(),
    );
  }

  Future<Book?> loadBook(String bookId) async {
    final file = File(p.join(_booksDirectory.path, '${_safeId(bookId)}.json'));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Book.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<void> saveBook(Book book) async {
    await _writeJson(
      File(p.join(_booksDirectory.path, '${_safeId(book.id)}.json')),
      book.toJson(),
    );
  }

  Future<void> deleteBook(String bookId) async {
    final safeId = _safeId(bookId);
    final bookFile = File(p.join(_booksDirectory.path, '$safeId.json'));
    if (await bookFile.exists()) {
      await bookFile.delete();
    }

    if (await _translationsDirectory.exists()) {
      await for (final entity in _translationsDirectory.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('${safeId}_') && name.endsWith('.json')) {
          await entity.delete();
        }
      }
    }
  }

  Future<TranslationRecord?> loadTranslation(
    String bookId,
    String language,
  ) async {
    final file = _translationFile(bookId, language);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return TranslationRecord.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<void> saveTranslation(TranslationRecord record) async {
    await _writeJson(
      _translationFile(record.bookId, record.targetLanguage),
      record.toJson(),
    );
  }

  Future<void> deleteTranslation(String bookId, String language) async {
    final file = _translationFile(bookId, language);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// All translated language codes across the library, used for home stats.
  Future<Set<String>> translatedLanguages() async {
    final languages = <String>{};
    if (!await _translationsDirectory.exists()) return languages;
    await for (final entity in _translationsDirectory.list()) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      final separator = name.lastIndexOf('_');
      if (separator == -1 || separator == name.length - 1) continue;
      languages.add(name.substring(separator + 1));
    }
    return languages;
  }

  File _translationFile(String bookId, String language) {
    final safeLanguage = _safeId(language);
    return File(
      p.join(
        _translationsDirectory.path,
        '${_safeId(bookId)}_$safeLanguage.json',
      ),
    );
  }

  Future<void> _writeJson(File file, Object data) {
    final previous = _pendingWrites[file.path] ?? Future<void>.value();
    final next = previous.then<void>(
      (_) => _performWrite(file, data),
      onError: (_) => _performWrite(file, data),
    );
    _pendingWrites[file.path] = next;
    next.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_pendingWrites[file.path], next)) {
        _pendingWrites.remove(file.path);
      }
    });
    return next;
  }

  Future<void> _performWrite(File file, Object data) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  String _safeId(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return safe.isEmpty ? 'unknown' : safe;
  }
}
