import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/language.dart';
import '../services/local_store.dart';
import '../services/translation/book_translator.dart';
import '../services/translation/translation_engine.dart';

enum TranslationJobStatus { running, completed, failed, cancelled }

class TranslationJobState {
  TranslationJobState({
    required this.bookId,
    required this.bookTitle,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.startedAt,
  });

  final String bookId;
  final String bookTitle;
  final AppLanguage sourceLanguage;
  final AppLanguage targetLanguage;
  final DateTime startedAt;

  TranslationJobStatus status = TranslationJobStatus.running;
  int completedChunks = 0;
  int totalChunks = 0;
  int currentChapterIndex = 0;
  int currentChapterChunk = 0;
  String currentChapterTitle = '';
  String? error;
  bool cancelRequested = false;

  bool get isRunning => status == TranslationJobStatus.running;
  double get fraction =>
      totalChunks == 0 ? 0 : (completedChunks / totalChunks).clamp(0.0, 1.0);
  int get percent => (fraction * 100).round();
}

/// Coordinates one active translation job and caches translated records.
class TranslationController extends ChangeNotifier {
  factory TranslationController({
    required LocalStore store,
    Future<void> Function()? onTranslationsChanged,
    BookTranslator translator = const BookTranslator(),
  }) {
    return TranslationController._(store, onTranslationsChanged, translator);
  }

  TranslationController._(
    this.store,
    this.onTranslationsChanged,
    this._translator,
  );

  final LocalStore store;
  final Future<void> Function()? onTranslationsChanged;
  final BookTranslator _translator;

  final Map<String, TranslationRecord?> _cache = {};
  TranslationJobState? _activeJob;
  bool _cancelRequested = false;

  TranslationJobState? get activeJob => _activeJob;
  bool get isTranslating => _activeJob?.isRunning ?? false;

  static String cacheKey(String bookId, String language) =>
      '$bookId::$language';

  TranslationRecord? recordFor(String bookId, String language) {
    return _cache[cacheKey(bookId, language)];
  }

  Future<TranslationRecord?> loadTranslation(
    String bookId,
    String language, {
    bool force = false,
  }) async {
    final key = cacheKey(bookId, language);
    if (!force && _cache.containsKey(key)) return _cache[key];
    final record = await store.loadTranslation(bookId, language);
    _cache[key] = record;
    return record;
  }

  /// Runs the whole book in one call. Returns `null` on failure or cancel.
  Future<TranslationRecord?> startTranslation({
    required Book book,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
    required TranslationEngine engine,
  }) async {
    if (_activeJob?.isRunning ?? false) {
      throw const TranslationException('已有翻译任务正在进行，请先等待或取消');
    }
    if (targetLanguage.isAuto) {
      throw const TranslationException('请选择目标语言');
    }

    _cancelRequested = false;
    final job = TranslationJobState(
      bookId: book.id,
      bookTitle: book.title,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      startedAt: DateTime.now(),
    );
    _activeJob = job;
    notifyListeners();

    try {
      final record = await _translator.translate(
        book: book,
        engine: engine,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        onProgress: (progress) {
          job
            ..completedChunks = progress.completedChunks
            ..totalChunks = progress.totalChunks
            ..currentChapterIndex = progress.currentChapterIndex
            ..currentChapterTitle = progress.currentChapterTitle
            ..currentChapterChunk = progress.currentChapterChunk;
          notifyListeners();
        },
        isCancelled: () => _cancelRequested,
      );

      await store.saveTranslation(record);
      _cache[cacheKey(book.id, targetLanguage.code)] = record;
      job
        ..status = TranslationJobStatus.completed
        ..completedChunks = job.totalChunks;
      await onTranslationsChanged?.call();
      notifyListeners();
      return record;
    } on TranslationCancelledException {
      job.status = TranslationJobStatus.cancelled;
      notifyListeners();
      return null;
    } on TranslationException catch (error) {
      job
        ..status = TranslationJobStatus.failed
        ..error = error.message;
      notifyListeners();
      return null;
    } on Object catch (error) {
      job
        ..status = TranslationJobStatus.failed
        ..error = '翻译过程中出现错误：$error';
      notifyListeners();
      return null;
    } finally {
      engine.close();
      _cancelRequested = false;
    }
  }

  void cancelTranslation() {
    if (!(_activeJob?.isRunning ?? false)) return;
    _cancelRequested = true;
    _activeJob!.cancelRequested = true;
    notifyListeners();
  }

  void cancelIfRunningFor(String bookId) {
    final job = _activeJob;
    if (job != null && job.isRunning && job.bookId == bookId) {
      cancelTranslation();
    }
  }

  void clearFinishedJob() {
    if (_activeJob?.isRunning ?? false) return;
    _activeJob = null;
    notifyListeners();
  }

  /// Drop cached translations when a book is removed.
  void evictBook(String bookId) {
    _cache.removeWhere((key, value) => key.startsWith('$bookId::'));
    if (_activeJob?.bookId == bookId && !(_activeJob?.isRunning ?? false)) {
      _activeJob = null;
    }
    notifyListeners();
  }
}
