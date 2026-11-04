import '../../models/book.dart';
import '../../models/language.dart';
import 'text_chunker.dart';
import 'translation_engine.dart';

class TranslationProgress {
  const TranslationProgress({
    required this.completedChunks,
    required this.totalChunks,
    required this.currentChapterIndex,
    required this.currentChapterTitle,
    required this.currentChapterChunk,
  });

  final int completedChunks;
  final int totalChunks;
  final int currentChapterIndex;
  final String currentChapterTitle;
  final int currentChapterChunk;

  double get fraction {
    if (totalChunks == 0) return 0;
    return (completedChunks / totalChunks).clamp(0.0, 1.0);
  }

  int get percent => (fraction * 100).round();
}

/// Runs a book through a [TranslationEngine] one chunk at a time.
///
/// Serial requests are intentional: free API keys usually enforce low QPS.
class BookTranslator {
  const BookTranslator();

  Future<TranslationRecord> translate({
    required Book book,
    required TranslationEngine engine,
    required AppLanguage sourceLanguage,
    required AppLanguage targetLanguage,
    required void Function(TranslationProgress progress) onProgress,
    required bool Function() isCancelled,
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

    var completed = 0;
    final translatedChapters = <TranslatedChapter>[];
    onProgress(
      TranslationProgress(
        completedChunks: 0,
        totalChunks: totalChunks,
        currentChapterIndex: 0,
        currentChapterTitle: plans.first.chapter.title,
        currentChapterChunk: 0,
      ),
    );

    for (final plan in plans) {
      final chapterPieces = <String>[];
      for (var chunkIndex = 0; chunkIndex < plan.chunks.length; chunkIndex++) {
        _throwIfCancelled(isCancelled);
        final translated = await _translateWithRetry(
          engine: engine,
          text: plan.chunks[chunkIndex],
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          isCancelled: isCancelled,
          retryDelay: retryDelay,
          maxAttempts: maxAttempts,
        );
        _throwIfCancelled(isCancelled);
        chapterPieces.add(translated);
        completed++;

        onProgress(
          TranslationProgress(
            completedChunks: completed,
            totalChunks: totalChunks,
            currentChapterIndex: plan.chapter.index,
            currentChapterTitle: plan.chapter.title,
            currentChapterChunk: chunkIndex + 1,
          ),
        );

        if (completed < totalChunks && requestInterval > Duration.zero) {
          await _waitWithCancellation(requestInterval, isCancelled);
        }
      }

      translatedChapters.add(
        TranslatedChapter(
          chapterId: plan.chapter.id,
          chapterIndex: plan.chapter.index,
          title: plan.chapter.title,
          text: chapterPieces.join('\n\n').trim(),
        ),
      );
    }

    _throwIfCancelled(isCancelled);

    return TranslationRecord(
      bookId: book.id,
      sourceLanguage: sourceLanguage.code,
      targetLanguage: targetLanguage.code,
      providerId: engine.id,
      createdAt: DateTime.now(),
      chapters: translatedChapters,
    );
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
      _throwIfCancelled(isCancelled);
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
      _throwIfCancelled(isCancelled);
      final slice = remaining < step ? remaining : step;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
    _throwIfCancelled(isCancelled);
  }

  void _throwIfCancelled(bool Function() isCancelled) {
    if (isCancelled()) throw const TranslationCancelledException();
  }
}

class _ChapterPlan {
  const _ChapterPlan(this.chapter, this.chunks);

  final BookChapter chapter;
  final List<String> chunks;
}
