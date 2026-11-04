import 'dart:math' as math;

import '../../core/utils/id_generator.dart';
import '../../core/utils/text_utils.dart';
import '../../models/book.dart';
import '../../models/language.dart';

/// A detected adjacent pair that looks like one original paragraph followed by
/// its translation in another supported language.
///
/// Detection is intentionally local and heuristic: it never calls the
/// translation API. The UI shows both sides and the user decides whether to
/// remove the foreign paragraph.
class DedupeCandidate {
  const DedupeCandidate({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.keepLineIndex,
    required this.removeLineIndex,
    required this.keepLanguage,
    required this.removeLanguage,
    required this.keepText,
    required this.removeText,
  });

  final int chapterIndex;
  final String chapterTitle;
  final int keepLineIndex;
  final int removeLineIndex;
  final AppLanguage keepLanguage;
  final AppLanguage removeLanguage;
  final String keepText;
  final String removeText;

  String get id => '$chapterIndex:$keepLineIndex:$removeLineIndex';

  int get removableCharacters => countVisibleCharacters(removeText);
}

class DedupeAnalysis {
  const DedupeAnalysis({
    required this.sourceBook,
    required this.keepLanguage,
    required this.candidates,
    required this.scannedParagraphs,
  });

  final Book sourceBook;
  final AppLanguage keepLanguage;
  final List<DedupeCandidate> candidates;
  final int scannedParagraphs;

  int get affectedChapterCount =>
      candidates.map((candidate) => candidate.chapterIndex).toSet().length;

  int get removableCharacterCount => candidates.fold<int>(
    0,
    (sum, candidate) => sum + candidate.removableCharacters,
  );

  int get removableParagraphCount => candidates.length;
}

class DedupeException implements Exception {
  const DedupeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Local multilingual paragraph analysis and book generation.
abstract final class MultilingualDedupeService {
  static const Set<String> supportedLanguageCodes = {'zh', 'ja', 'ko', 'en'};

  /// Supported languages, in the display order used by the dedupe UI.
  static const List<AppLanguage> supportedLanguages = [
    Languages.zh,
    Languages.ja,
    Languages.en,
    Languages.ko,
  ];

  static DedupeAnalysis analyze(
    Book book, {
    required AppLanguage keepLanguage,
  }) {
    if (!supportedLanguageCodes.contains(keepLanguage.code)) {
      throw const DedupeException('请选择中文、日语、英语或韩语作为保留语言');
    }

    final candidates = <DedupeCandidate>[];
    var scannedParagraphs = 0;

    for (final chapter in book.chapters) {
      final paragraphs = _paragraphsOf(chapter);
      scannedParagraphs += paragraphs.length;
      final usedParagraphs = <int>{};

      for (var index = 0; index < paragraphs.length - 1; index++) {
        if (usedParagraphs.contains(index) ||
            usedParagraphs.contains(index + 1)) {
          continue;
        }
        final first = paragraphs[index];
        final second = paragraphs[index + 1];
        final firstLanguage = first.language;
        final secondLanguage = second.language;

        if (firstLanguage == null || secondLanguage == null) continue;
        if (firstLanguage.code == secondLanguage.code) continue;
        if (!supportedLanguageCodes.contains(firstLanguage.code) ||
            !supportedLanguageCodes.contains(secondLanguage.code)) {
          continue;
        }

        final firstIsKeep = firstLanguage.code == keepLanguage.code;
        final secondIsKeep = secondLanguage.code == keepLanguage.code;
        if (!firstIsKeep && !secondIsKeep) continue;

        final keep = firstIsKeep ? first : second;
        final remove = firstIsKeep ? second : first;
        if (!_looksLikeTranslationPair(
          keep.text,
          remove.text,
          keep.language!,
          remove.language!,
        )) {
          continue;
        }

        usedParagraphs
          ..add(index)
          ..add(index + 1);
        candidates.add(
          DedupeCandidate(
            chapterIndex: chapter.index,
            chapterTitle: chapter.title,
            keepLineIndex: keep.lineIndex,
            removeLineIndex: remove.lineIndex,
            keepLanguage: keep.language!,
            removeLanguage: remove.language!,
            keepText: keep.text,
            removeText: remove.text,
          ),
        );
      }
    }

    return DedupeAnalysis(
      sourceBook: book,
      keepLanguage: keepLanguage,
      candidates: List.unmodifiable(candidates),
      scannedParagraphs: scannedParagraphs,
    );
  }

  /// Removes every selected foreign paragraph and returns a new book.
  ///
  /// The source book is never modified. Chapters that become empty are omitted
  /// and remaining chapter indices are rebuilt.
  static Book generateDedupedBook({
    required Book source,
    required AppLanguage keepLanguage,
    required Iterable<DedupeCandidate> selected,
  }) {
    final selectedList = selected.toList(growable: false);
    if (selectedList.isEmpty) {
      throw const DedupeException('请至少勾选一组要移除的段落');
    }
    if (selectedList.any(
      (candidate) => candidate.keepLanguage.code != keepLanguage.code,
    )) {
      throw const DedupeException('保留语言与所选段落不一致，请重新分析');
    }

    final removalsByChapter = <int, Set<int>>{};
    for (final candidate in selectedList) {
      removalsByChapter
          .putIfAbsent(candidate.chapterIndex, () => <int>{})
          .add(candidate.removeLineIndex);
    }

    final chapters = <BookChapter>[];
    for (final sourceChapter in source.chapters) {
      final removals = removalsByChapter[sourceChapter.index];
      if (removals == null || removals.isEmpty) {
        chapters.add(
          BookChapter(
            id: 'chapter_${chapters.length}',
            index: chapters.length,
            title: sourceChapter.title,
            text: sourceChapter.text,
          ),
        );
        continue;
      }

      final lines = normalizeLineEndings(sourceChapter.text).split('\n');
      final keptLines = <String>[];
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        if (removals.contains(lineIndex)) continue;
        keptLines.add(lines[lineIndex]);
      }
      final text = _tidyBlankLines(keptLines);
      if (text.isEmpty) continue;

      chapters.add(
        BookChapter(
          id: 'chapter_${chapters.length}',
          index: chapters.length,
          title: sourceChapter.title,
          text: text,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const DedupeException('所选内容移除后没有剩余正文');
    }

    final charCount = chapters.fold<int>(
      0,
      (sum, chapter) => sum + countVisibleCharacters(chapter.text),
    );
    final titleSuffix = '（${keepLanguage.label}去重版）';

    return Book(
      meta: BookMeta(
        id: generateId('book_'),
        title: '${source.title}$titleSuffix',
        author: source.author,
        fileName: source.meta.fileName,
        format: source.meta.format,
        chapterCount: chapters.length,
        charCount: charCount,
        importedAt: DateTime.now(),
      ),
      chapters: chapters,
    );
  }

  /// Best-effort script detection for the four supported languages.
  ///
  /// Japanese kana and Korean Hangul are strong signals; Chinese is inferred
  /// from Han characters without kana/Hangul; English from Latin letters.
  static AppLanguage? detectLanguage(String text) {
    final hangul = RegExp(
      r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]',
    ).allMatches(text).length;
    if (hangul > 0) return Languages.ko;

    final kana = RegExp(
      r'[\u3040-\u30FF\u31F0-\u31FF]',
    ).allMatches(text).length;
    if (kana > 0) return Languages.ja;

    final han = RegExp(
      r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]',
    ).allMatches(text).length;
    if (han > 0) return Languages.zh;

    final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
    if (latin >= 2) return Languages.en;

    return null;
  }

  static List<_Paragraph> _paragraphsOf(BookChapter chapter) {
    final lines = normalizeLineEndings(chapter.text).split('\n');
    final paragraphs = <_Paragraph>[];
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final text = lines[lineIndex].trim();
      if (text.isEmpty) continue;
      paragraphs.add(
        _Paragraph(
          lineIndex: lineIndex,
          text: text,
          language: detectLanguage(text),
        ),
      );
    }
    return paragraphs;
  }

  static bool _looksLikeTranslationPair(
    String keepText,
    String removeText,
    AppLanguage keepLanguage,
    AppLanguage removeLanguage,
  ) {
    final keepLength = countVisibleCharacters(keepText);
    final removeLength = countVisibleCharacters(removeText);
    if (keepLength < 3 || removeLength < 3) return false;

    final shorter = math.min(keepLength, removeLength);
    final longer = math.max(keepLength, removeLength);
    final involvesEnglish =
        keepLanguage.code == 'en' || removeLanguage.code == 'en';
    final maxRatio = involvesEnglish ? 5.0 : 3.0;
    return (longer / shorter) <= maxRatio;
  }

  static String _tidyBlankLines(List<String> lines) {
    final output = <String>[];
    var pendingBlank = false;
    for (final line in lines) {
      final trimmedRight = line.replaceAll(RegExp(r'[ \t]+$'), '');
      if (trimmedRight.trim().isEmpty) {
        pendingBlank = output.isNotEmpty;
        continue;
      }
      if (pendingBlank && output.isNotEmpty) output.add('');
      pendingBlank = false;
      output.add(trimmedRight);
    }
    return output.join('\n').trim();
  }
}

class _Paragraph {
  const _Paragraph({
    required this.lineIndex,
    required this.text,
    required this.language,
  });

  final int lineIndex;
  final String text;
  final AppLanguage? language;
}
