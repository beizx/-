import 'dart:typed_data';

import '../../core/utils/id_generator.dart';
import '../../core/utils/text_utils.dart';
import '../../models/book.dart';
import 'text_decoder.dart';

/// Parses TXT novels and applies lightweight chapter splitting.
abstract final class TxtParser {
  static const int autoSplitSize = 6000;

  static Book parse({
    required Uint8List bytes,
    required String fileName,
    String? bookId,
  }) {
    final decoded = cleanImportedText(decodeBookBytes(bytes));
    if (decoded.isEmpty) {
      throw const FormatException('这个 TXT 文件没有可读取的正文');
    }

    final leadingTitle = _extractLeadingBookTitle(decoded);
    final content = leadingTitle.content;
    final id = bookId ?? generateId('book_');
    final rawChapters = _splitIntoChapters(content);
    if (rawChapters.isEmpty) {
      throw const FormatException('未能从 TXT 文件中提取正文');
    }

    final chapters = <BookChapter>[];
    for (var index = 0; index < rawChapters.length; index++) {
      final chapter = rawChapters[index];
      chapters.add(
        BookChapter(
          id: 'chapter_$index',
          index: index,
          title: chapter.title,
          text: chapter.text,
        ),
      );
    }

    final title = leadingTitle.title ?? _titleFromFileName(fileName);
    final charCount = chapters.fold<int>(
      0,
      (sum, chapter) => sum + countVisibleCharacters(chapter.text),
    );

    return Book(
      meta: BookMeta(
        id: id,
        title: title,
        author: '未知作者',
        fileName: fileName,
        format: BookFormat.txt,
        chapterCount: chapters.length,
        charCount: charCount,
        importedAt: DateTime.now(),
      ),
      chapters: chapters,
    );
  }

  static List<_RawChapter> _splitIntoChapters(String content) {
    final text = cleanImportedText(content);
    final lines = text.split('\n');
    final headingIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (isChapterHeading(lines[i])) {
        headingIndexes.add(i);
      }
    }

    if (headingIndexes.isEmpty) {
      return _splitWithoutHeadings(lines);
    }

    final chapters = <_RawChapter>[];
    var currentTitle = '正文';
    var buffer = <String>[];

    void flush() {
      final body = _cleanChapterBody(buffer.join('\n'));
      if (body.isNotEmpty) {
        chapters.add(_RawChapter(currentTitle, body));
      }
      buffer = <String>[];
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (headingIndexes.contains(i)) {
        flush();
        currentTitle = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      } else {
        buffer.add(line);
      }
    }
    flush();

    if (chapters.isEmpty) {
      return _splitWithoutHeadings(lines);
    }
    return chapters;
  }

  static List<_RawChapter> _splitWithoutHeadings(List<String> lines) {
    final chunks = <String>[];
    var buffer = <String>[];
    var bufferLength = 0;

    void flush() {
      final body = _cleanChapterBody(buffer.join('\n'));
      if (body.isNotEmpty) chunks.add(body);
      buffer = <String>[];
      bufferLength = 0;
    }

    for (final line in lines) {
      final lineLength = line.runes.length;
      if (lineLength > autoSplitSize) {
        flush();
        for (final piece in _hardSplit(line)) {
          chunks.add(piece);
        }
        continue;
      }
      if (bufferLength + lineLength + 1 > autoSplitSize && buffer.isNotEmpty) {
        flush();
      }
      buffer.add(line);
      bufferLength += lineLength + 1;
    }
    flush();

    if (chunks.isEmpty) return const [];
    if (chunks.length == 1) {
      return [_RawChapter('全文', chunks.first)];
    }
    return [
      for (var i = 0; i < chunks.length; i++)
        _RawChapter('第 ${i + 1} 节', chunks[i]),
    ];
  }

  static Iterable<String> _hardSplit(String line) sync* {
    final runes = line.runes.toList();
    for (var start = 0; start < runes.length; start += autoSplitSize) {
      final end = (start + autoSplitSize).clamp(0, runes.length);
      final piece = String.fromCharCodes(runes.sublist(start, end)).trim();
      if (piece.isNotEmpty) yield piece;
    }
  }

  static String _cleanChapterBody(String text) {
    final lines = normalizeLineEndings(text)
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trimRight())
        .toList();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n').trim();
  }

  static String _titleFromFileName(String fileName) {
    final baseName = fileName.split(RegExp(r'[/\\]')).last;
    final dot = baseName.lastIndexOf('.');
    final title = (dot == -1 ? baseName : baseName.substring(0, dot)).trim();
    return title.isEmpty ? '未命名书籍' : title;
  }

  /// Many downloaded TXT novels start with `《书名》`. Treat that as metadata
  /// instead of a one-line "正文" chapter, but keep the title when it is the
  /// only line in the file.
  static ({String content, String? title}) _extractLeadingBookTitle(
    String content,
  ) {
    final lines = content.split('\n');
    var firstLineIndex = 0;
    while (firstLineIndex < lines.length &&
        lines[firstLineIndex].trim().isEmpty) {
      firstLineIndex++;
    }
    if (firstLineIndex >= lines.length) {
      return (content: content, title: null);
    }

    final match = RegExp(
      r'^《\s*(.+?)\s*》$',
    ).firstMatch(lines[firstLineIndex].trim());
    if (match == null) return (content: content, title: null);

    final title = match.group(1)?.trim();
    if (title == null || title.isEmpty) {
      return (content: content, title: null);
    }
    final remaining = lines.sublist(firstLineIndex + 1).join('\n').trim();
    if (remaining.isEmpty) {
      return (content: content, title: null);
    }
    return (content: remaining, title: title);
  }

  static final RegExp _numberedChapter = RegExp(
    r'^第\s*[0-9零〇一二三四五六七八九十百千万两]+\s*[章节回卷部篇集话話幕](?:\s*[：:·—\-]?\s*.{0,30})?$',
  );

  static final RegExp _koreanChapter = RegExp(
    r'^제\s*\d+\s*[장화권부편](?:\s+.{0,30})?$',
  );

  static final RegExp _englishChapter = RegExp(
    r'^(chapter|part|book|volume)\s+(\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)\b.{0,45}$',
    caseSensitive: false,
  );

  static final RegExp _fixedHeading = RegExp(
    r'^(序章|楔子|引子|序言|前言|前序|后记|後記|尾声|尾聲|终章|終章|番外|附录|附錄|プロローグ|エピローグ|프롤로그|에필로그|prologue|epilogue|afterword|foreword)(?:\s*[：:·—\-]?\s*.{0,30})?$',
    caseSensitive: false,
  );

  /// Public so tests (and future formats) can reuse the same heuristic.
  static bool isChapterHeading(String line) {
    final text = line.trim();
    if (text.isEmpty || text.runes.length > 60) return false;
    if (text.endsWith('。') ||
        text.endsWith('！') ||
        text.endsWith('？') ||
        text.endsWith('!') ||
        text.endsWith('?')) {
      return false;
    }
    return _numberedChapter.hasMatch(text) ||
        _koreanChapter.hasMatch(text) ||
        _englishChapter.hasMatch(text) ||
        _fixedHeading.hasMatch(text);
  }
}

class _RawChapter {
  const _RawChapter(this.title, this.text);

  final String title;
  final String text;
}
