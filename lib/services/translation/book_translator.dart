import '../../models/book.dart';
import '../../models/language.dart';
import '../../models/translation_draft.dart';
import 'text_chunker.dart';
import 'translation_engine.dart';

class TranslationProgress {
  const TranslationProgress({
    required this.completedChunks,
    required this.totalChunks,
    required this.currentChapterIndex,
    required this.currentChapterTitle,
    required this.currentChapterChunk,
    this.failedChunks = 0,
    this.skippedChunks = 0,
    this.estimatedRemaining,
    this.retryingFailures = false,
  });

  final int completedChunks;
  final int totalChunks;
  final int currentChapterIndex;
  final String currentChapterTitle;
  final int currentChapterChunk;
  final int failedChunks;
  final int skippedChunks;
  final Duration? estimatedRemaining;
  final bool retryingFailures;

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

/// Outcome of one translation pass.
///
/// [record] is set only when every chunk succeeded. [draft] always reflects
/// the chunks that are safe to resume from, including a cancel mid-book.
class TranslationRunResult {
  const TranslationRunResult({
    required this.draft,
    required this.cancelled,
    this.record,
  });

  final TranslationDraft draft;
  final bool cancelled;
  final TranslationRecord? record;

  bool get complete => record?.complete ?? false;
}

/// Runs a book through a [TranslationEngine] one chunk at a time.
///
/// Serial requests are intentional: free API keys usually enforce low QPS.
/// Successful chunks are checkpointed so cancel, failure and process death
/// can resume the same book and target language without repeating them.
class BookTranslator {
  const BookTranslator();

  Future<TranslationRunResult> translate({
    required Book book,
    required TranslationEngine engine,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
    required void Function(TranslationProgress progress) onProgress,
    required bool Function() isCancelled,
    TranslationDraft? resume,
    bool retryFailuresOnly = false,
    Future<void> Function(TranslationDraft draft)? onCheckpoint,
    Duration requestInterval = const Duration(milliseconds: 1100),
    Duration retryDelay = const Duration(seconds: 2),
    int maxAttempts = 3,
  }) async {
    if (book.chapters.isEmpty) {
      throw const TranslationException('这本书没有可翻译的章节');
    }
    if (targetLanguage.isAuto) {
      throw const TranslationException('请选择目标语言');
    }

    final plans = <_ChapterPlan>[];
    var totalChunks = 0;
    for (final chapter in book.chapters) {
      final chunks = TextChunker.chunk(chapter.text);
      plans.add(_ChapterPlan(chapter, chunks));
      totalChunks += chunks.length;
    }
    if (totalChunks == 0) {
      throw const TranslationException('这本书没有可翻译的正文');
    }

    final usable = _usableResume(
      resume,
      bookId: book.id,
      sourceLanguage: sourceLanguage.code,
      targetLanguage: targetLanguage.code,
    );
    final builder = _DraftBuilder(
      bookId: book.id,
      sourceLanguage: sourceLanguage.code,
      targetLanguage: targetLanguage.code,
      providerId: engine.id,
      totalChunks: totalChunks,
    )..seed(usable);
    builder.retain(plans);
    final failuresOnly = retryFailuresOnly && builder.failedKeys.isNotEmpty;

    final started = DateTime.now();
    var measured = 0;
    var translatedThisRun = 0;
    var failedThisRun = 0;

    TranslationProgress progressFor(_ChapterPlan plan, int chunkIndex) {
      final snapshot = builder.snapshot();
      return TranslationProgress(
        completedChunks: snapshot.succeeded,
        totalChunks: totalChunks,
        currentChapterIndex: plan.chapter.index,
        currentChapterTitle: plan.chapter.title,
        currentChapterChunk: chunkIndex,
        failedChunks: snapshot.failedChunks,
        skippedChunks: builder.skipped,
        estimatedRemaining: _estimateRemaining(
          started: started,
          measured: measured,
          remaining: snapshot.remainingChunks,
        ),
        retryingFailures: failuresOnly,
      );
    }

    Future<void> checkpoint() async {
      final draft = builder.snapshot();
      await onCheckpoint?.call(draft);
    }

    onProgress(progressFor(plans.first, 0));

    for (final plan in plans) {
      for (var chunkIndex = 0; chunkIndex < plan.chunks.length; chunkIndex++) {
        final source = plan.chunks[chunkIndex];
        final key = TranslationDraft.keyFor(plan.chapter.id, chunkIndex);
        final hash = TranslationDraft.fingerprint(source);
        final saved = builder.chunks[key];
        final alreadyDone = saved != null && saved.hash == hash;
        if (saved != null && saved.hash != hash) {
          builder.chunks.remove(key);
          builder.failedKeys.remove(key);
        }

        if (alreadyDone) {
          builder.failedKeys.remove(key);
          builder.skipped++;
          onProgress(progressFor(plan, chunkIndex + 1));
          continue;
        }

        final failedBefore = builder.failedKeys.contains(key);
        if (failuresOnly && !failedBefore) {
          continue;
        }

        if (isCancelled()) {
          return _finish(
            book: book,
            builder: builder,
            cancelled: true,
            translatedThisRun: translatedThisRun,
            failedThisRun: failedThisRun,
          );
        }

        try {
          final translated = await _translateWithRetry(
            engine: engine,
            text: source,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            isCancelled: isCancelled,
            retryDelay: retryDelay,
            maxAttempts: maxAttempts,
          );
          builder.chunks[key] = SavedChunk(hash: hash, text: translated);
          builder.failedKeys.remove(key);
          translatedThisRun++;
          measured++;
          await checkpoint();
          onProgress(progressFor(plan, chunkIndex + 1));

          if (isCancelled()) {
            return _finish(
              book: book,
              builder: builder,
              cancelled: true,
              translatedThisRun: translatedThisRun,
              failedThisRun: failedThisRun,
            );
          }

          final snapshot = builder.snapshot();
          final moreWork = failuresOnly
              ? snapshot.failedChunks > 0
              : snapshot.remainingChunks > 0 || snapshot.failedChunks > 0;
          if (moreWork && requestInterval > Duration.zero) {
            await _waitWithCancellation(requestInterval, isCancelled);
          }
        } on TranslationCancelledException {
          return _finish(
            book: book,
            builder: builder,
            cancelled: true,
            translatedThisRun: translatedThisRun,
            failedThisRun: failedThisRun,
          );
        } on TranslationException {
          builder.chunks.remove(key);
          if (!builder.failedKeys.contains(key)) {
            builder.failedKeys.add(key);
          }
          failedThisRun++;
          measured++;
          await checkpoint();
          onProgress(progressFor(plan, chunkIndex + 1));
          if (isCancelled()) {
            return _finish(
              book: book,
              builder: builder,
              cancelled: true,
              translatedThisRun: translatedThisRun,
              failedThisRun: failedThisRun,
            );
          }
          final afterFailure = builder.snapshot();
          final moreAfterFailure = failuresOnly
              ? afterFailure.failedChunks > 0
              : afterFailure.remainingChunks > 0 ||
                    afterFailure.failedChunks > 0;
          if (moreAfterFailure && requestInterval > Duration.zero) {
            await _waitWithCancellation(requestInterval, isCancelled);
          }
        }
      }
    }

    if (isCancelled()) {
      return _finish(
        book: book,
        builder: builder,
        cancelled: true,
        translatedThisRun: translatedThisRun,
        failedThisRun: failedThisRun,
      );
    }

    return _finish(
      book: book,
      builder: builder,
      cancelled: false,
      translatedThisRun: translatedThisRun,
      failedThisRun: failedThisRun,
    );
  }

  TranslationRunResult _finish({
    required Book book,
    required _DraftBuilder builder,
    required bool cancelled,
    required int translatedThisRun,
    required int failedThisRun,
  }) {
    if (cancelled && translatedThisRun == 0 && failedThisRun == 0) {
      throw const TranslationCancelledException();
    }
    final draft = builder.snapshot();
    final record = recordFromDraft(book: book, draft: draft);
    final finished = !cancelled && record != null && record.complete;
    return TranslationRunResult(
      draft: draft,
      cancelled: cancelled,
      record: finished ? record : null,
    );
  }

  TranslationDraft? _usableResume(
    TranslationDraft? resume, {
    required String bookId,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    if (resume == null) return null;
    if (resume.bookId != bookId) return null;
    if (resume.targetLanguage != targetLanguage) return null;
    if (resume.sourceLanguage != sourceLanguage) return null;
    return resume;
  }

  Duration? _estimateRemaining({
    required DateTime started,
    required int measured,
    required int remaining,
  }) {
    if (measured <= 0 || remaining <= 0) return null;
    final elapsed = DateTime.now().difference(started);
    final micros = elapsed.inMicroseconds * remaining ~/ measured;
    if (micros <= 0) return null;
    return Duration(microseconds: micros);
  }

  Future<String> _translateWithRetry({
    required TranslationEngine engine,
    required String text,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
    required bool Function() isCancelled,
    required Duration retryDelay,
    required int maxAttempts,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (isCancelled()) throw const TranslationCancelledException();
      try {
        return await engine.translate(
          text: text,
          sourceLanguage: sourceLanguage.code,
          targetLanguage: targetLanguage.code,
        );
      } on TranslationCancelledException {
        rethrow;
      } on TranslationException catch (error) {
        if (!error.retryable || attempt >= maxAttempts) rethrow;
        final wait = retryDelay * attempt;
        await _waitWithCancellation(wait, isCancelled);
      } on Object catch (error) {
        if (attempt >= maxAttempts) {
          throw TranslationException('翻译请求失败：$error');
        }
        await _waitWithCancellation(retryDelay * attempt, isCancelled);
      }
    }
    throw const TranslationException('翻译请求失败');
  }

  Future<void> _waitWithCancellation(
    Duration duration,
    bool Function() isCancelled,
  ) async {
    const step = Duration(milliseconds: 100);
    var remaining = duration;
    while (remaining > Duration.zero) {
      if (isCancelled()) throw const TranslationCancelledException();
      final slice = remaining < step ? remaining : step;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
    if (isCancelled()) throw const TranslationCancelledException();
  }
}

/// Rebuilds a [TranslationRecord] from chunk drafts.
///
/// Chapters missing any chunk are omitted. [TranslationRecord.complete] is
/// true only when every chapter with body text is present and nothing failed.
TranslationRecord? recordFromDraft({
  required Book book,
  required TranslationDraft draft,
}) {
  final chapters = <TranslatedChapter>[];
  var allComplete = draft.failedKeys.isEmpty;
  var sawBody = false;
  for (final chapter in book.chapters) {
    final pieces = TextChunker.chunk(chapter.text);
    if (pieces.isEmpty) continue;
    sawBody = true;
    final translated = <String>[];
    var chapterDone = true;
    for (var index = 0; index < pieces.length; index++) {
      final key = TranslationDraft.keyFor(chapter.id, index);
      final saved = draft.chunks[key];
      final hash = TranslationDraft.fingerprint(pieces[index]);
      if (saved == null || saved.hash != hash) {
        chapterDone = false;
        break;
      }
      translated.add(saved.text);
    }
    if (!chapterDone) {
      allComplete = false;
      continue;
    }
    chapters.add(
      TranslatedChapter(
        chapterId: chapter.id,
        chapterIndex: chapter.index,
        title: chapter.title,
        text: translated.join('\n\n').trim(),
      ),
    );
  }
  if (!sawBody || chapters.isEmpty) return null;
  return TranslationRecord(
    bookId: draft.bookId,
    sourceLanguage: draft.sourceLanguage,
    targetLanguage: draft.targetLanguage,
    providerId: draft.providerId,
    createdAt: draft.updatedAt,
    chapters: chapters,
    complete: allComplete && chapters.length == _bodyChapterCount(book),
  );
}

int _bodyChapterCount(Book book) {
  var count = 0;
  for (final chapter in book.chapters) {
    if (TextChunker.chunk(chapter.text).isNotEmpty) count++;
  }
  return count;
}

/// Short Chinese label for a remaining-time estimate.
String formatTranslationEta(Duration duration) {
  if (duration.inSeconds < 45) return '不到 1 分钟';
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return '$hours 小时';
  return '$hours 小时 $rest 分钟';
}

class _DraftBuilder {
  _DraftBuilder({
    required this.bookId,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.providerId,
    required this.totalChunks,
  });

  final String bookId;
  final String sourceLanguage;
  final String targetLanguage;
  final String providerId;
  final int totalChunks;
  final Map<String, SavedChunk> chunks = {};
  final List<String> failedKeys = [];
  int skipped = 0;

  void seed(TranslationDraft? draft) {
    if (draft == null) return;
    chunks.addAll(draft.chunks);
    for (final key in draft.failedKeys) {
      if (!chunks.containsKey(key)) failedKeys.add(key);
    }
  }

  /// Drops chunks that no longer match the current book, including edits.
  void retain(List<_ChapterPlan> plans) {
    final valid = <String>{};
    for (final plan in plans) {
      for (var index = 0; index < plan.chunks.length; index++) {
        final key = TranslationDraft.keyFor(plan.chapter.id, index);
        valid.add(key);
        final saved = chunks[key];
        if (saved != null &&
            saved.hash != TranslationDraft.fingerprint(plan.chunks[index])) {
          chunks.remove(key);
          failedKeys.remove(key);
        }
      }
    }
    chunks.removeWhere((key, _) => !valid.contains(key));
    failedKeys.removeWhere((key) => !valid.contains(key));
  }

  TranslationDraft snapshot() {
    return TranslationDraft(
      bookId: bookId,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      providerId: providerId,
      updatedAt: DateTime.now(),
      totalChunks: totalChunks,
      chunks: Map<String, SavedChunk>.from(chunks),
      failedKeys: List<String>.from(failedKeys),
    );
  }
}

class _ChapterPlan {
  const _ChapterPlan(this.chapter, this.chunks);

  final BookChapter chapter;
  final List<String> chunks;
}
