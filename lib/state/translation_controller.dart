import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/language.dart';
import '../models/translation_draft.dart';
import '../services/local_store.dart';
import '../services/translation/book_translator.dart';
import '../services/translation/translation_engine.dart';

enum TranslationJobStatus { running, completed, failed, cancelled, partial }

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
  int failedChunks = 0;
  int currentChapterIndex = 0;
  int currentChapterChunk = 0;
  String currentChapterTitle = '';
  String? error;
  bool cancelRequested = false;
  bool retryingFailures = false;
  Duration? estimatedRemaining;

  bool get isRunning => status == TranslationJobStatus.running;

  int get remainingChunks {
    final left = totalChunks - completedChunks - failedChunks;
    return left < 0 ? 0 : left;
  }

  double get fraction {
    if (totalChunks == 0) return 0;
    final settled = completedChunks + failedChunks;
    return (settled / totalChunks).clamp(0.0, 1.0);
  }

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
  final Map<String, TranslationDraft?> _drafts = {};
  TranslationJobState? _activeJob;
  bool _cancelRequested = false;

  TranslationJobState? get activeJob => _activeJob;
  bool get isTranslating => _activeJob?.isRunning ?? false;

  static String cacheKey(String bookId, String language) =>
      '$bookId::$language';

  TranslationRecord? recordFor(String bookId, String language) {
    return _cache[cacheKey(bookId, language)];
  }

  TranslationDraft? draftFor(String bookId, String language) {
    return _drafts[cacheKey(bookId, language)];
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

  Future<TranslationDraft?> loadDraft(String bookId, String language) async {
    final key = cacheKey(bookId, language);
    final draft = await store.loadDraft(bookId, language);
    _drafts[key] = draft;
    return draft;
  }

  /// Drops an in-progress draft. A finished translation is left in place;
  /// a partial record that only existed for the draft is removed with it.
  Future<void> discardDraft(String bookId, String language) async {
    final key = cacheKey(bookId, language);
    await store.deleteDraft(bookId, language);
    _drafts[key] = null;
    final record = _cache[key] ?? await store.loadTranslation(bookId, language);
    if (record != null && !record.complete) {
      await store.deleteTranslation(bookId, language);
      _cache[key] = null;
    }
    notifyListeners();
  }

  /// Runs the whole book in one call. Returns the finished record, or `null`
  /// when the run was cancelled, still has failed chunks, or failed outright.
  ///
  /// [resume] reuses the saved draft for this book and target language.
  /// [retryFailuresOnly] translates chunks that previously failed and leaves
  /// successes untouched.
  Future<TranslationRecord?> startTranslation({
    required Book book,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
    required TranslationEngine engine,
    bool resume = true,
    bool retryFailuresOnly = false,
  }) async {
    if (_activeJob?.isRunning ?? false) {
      throw const TranslationException('已有翻译任务正在进行，请先等待或取消');
    }
    if (targetLanguage.isAuto) {
      throw const TranslationException('请选择目标语言');
    }

    _cancelRequested = false;
    final key = cacheKey(book.id, targetLanguage.code);
    final existing =
        _cache[key] ??
        await store.loadTranslation(book.id, targetLanguage.code);
    final preserveComplete = existing?.complete == true;
    TranslationDraft? resumeFrom;
    if (resume) {
      resumeFrom =
          _drafts[key] ?? await store.loadDraft(book.id, targetLanguage.code);
      if (resumeFrom != null &&
          resumeFrom.sourceLanguage != sourceLanguage.code) {
        resumeFrom = null;
      }
    } else {
      await store.deleteDraft(book.id, targetLanguage.code);
      _drafts[key] = null;
    }

    final job = TranslationJobState(
      bookId: book.id,
      bookTitle: book.title,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      startedAt: DateTime.now(),
    )..retryingFailures = retryFailuresOnly;
    _activeJob = job;
    notifyListeners();

    try {
      final result = await _translator.translate(
        book: book,
        engine: engine,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        resume: resumeFrom,
        retryFailuresOnly: retryFailuresOnly,
        onProgress: (progress) {
          job
            ..completedChunks = progress.completedChunks
            ..totalChunks = progress.totalChunks
            ..failedChunks = progress.failedChunks
            ..currentChapterIndex = progress.currentChapterIndex
            ..currentChapterTitle = progress.currentChapterTitle
            ..currentChapterChunk = progress.currentChapterChunk
            ..estimatedRemaining = progress.estimatedRemaining
            ..retryingFailures = progress.retryingFailures;
          notifyListeners();
        },
        onCheckpoint: (draft) => _persistDraft(
          book: book,
          draft: draft,
          preserveComplete: preserveComplete,
        ),
        isCancelled: () => _cancelRequested,
      );

      if (result.complete && result.record != null) {
        await store.saveTranslation(result.record!);
        await store.deleteDraft(book.id, targetLanguage.code);
        _cache[key] = result.record;
        _drafts[key] = null;
        job
          ..status = TranslationJobStatus.completed
          ..completedChunks = job.totalChunks
          ..failedChunks = 0
          ..estimatedRemaining = null;
        await onTranslationsChanged?.call();
        notifyListeners();
        return result.record;
      }

      await _persistDraft(
        book: book,
        draft: result.draft,
        preserveComplete: preserveComplete,
      );
      if (result.cancelled) {
        job.status = TranslationJobStatus.cancelled;
      } else if (result.draft.failedChunks > 0 ||
          result.draft.hasWorkRemaining) {
        job
          ..status = TranslationJobStatus.partial
          ..error = result.draft.failedChunks > 0
              ? '有 ${result.draft.failedChunks} 段翻译失败，成功的段落已保留'
              : '翻译未完成，已保留进度';
      } else {
        job.status = TranslationJobStatus.failed;
      }
      notifyListeners();
      return null;
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

  Future<void> _persistDraft({
    required Book book,
    required TranslationDraft draft,
    required bool preserveComplete,
  }) async {
    final key = cacheKey(book.id, draft.targetLanguage);
    await store.saveDraft(draft);
    _drafts[key] = draft;
    final readable = recordFromDraft(book: book, draft: draft);
    if (readable == null) return;
    if (readable.complete) {
      await store.saveTranslation(readable);
      await store.deleteDraft(book.id, readable.targetLanguage);
      _cache[key] = readable;
      _drafts[key] = null;
      return;
    }
    if (preserveComplete) return;
    await store.saveTranslation(readable);
    _cache[key] = readable;
  }

  void clearFinishedJob() {
    if (_activeJob?.isRunning ?? false) return;
    _activeJob = null;
    notifyListeners();
  }

  /// Drop cached translations when a book is removed.
  void evictBook(String bookId) {
    _cache.removeWhere((key, value) => key.startsWith('$bookId::'));
    _drafts.removeWhere((key, value) => key.startsWith('$bookId::'));
    if (_activeJob?.bookId == bookId && !(_activeJob?.isRunning ?? false)) {
      _activeJob = null;
    }
    notifyListeners();
  }
}
