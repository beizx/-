/// Splits long chapters into API-sized, paragraph-aware chunks.
///
/// Chunks never exceed [maxChars] code points. Paragraphs are packed with a
/// blank line, and an oversized paragraph is split on sentence punctuation
/// where possible.
abstract final class TextChunker {
  static const int defaultMaxChars = 1800;

  static List<String> chunk(String text, {int maxChars = defaultMaxChars}) {
    if (maxChars < 50) {
      throw ArgumentError.value(maxChars, 'maxChars', 'must be >= 50');
    }

    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ');
    final paragraphs = normalized
        .split(RegExp(r'\n+'))
        .map((paragraph) => paragraph.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((paragraph) => paragraph.isNotEmpty);

    final pieces = <String>[];
    for (final paragraph in paragraphs) {
      if (paragraph.runes.length <= maxChars) {
        pieces.add(paragraph);
      } else {
        pieces.addAll(_splitLongParagraph(paragraph, maxChars));
      }
    }

    final chunks = <String>[];
    final buffer = <String>[];
    var length = 0;
    const separator = '\n\n';

    void flush() {
      if (buffer.isEmpty) return;
      chunks.add(buffer.join(separator));
      buffer.clear();
      length = 0;
    }

    for (final piece in pieces) {
      final pieceLength = piece.runes.length;
      final addedLength = buffer.isEmpty
          ? pieceLength
          : pieceLength + separator.length;
      if (buffer.isNotEmpty && length + addedLength > maxChars) {
        flush();
      }
      buffer.add(piece);
      length += buffer.length == 1
          ? pieceLength
          : separator.length + pieceLength;
    }
    flush();
    return chunks;
  }

  static List<String> _splitLongParagraph(String paragraph, int maxChars) {
    final runes = paragraph.runes.toList();
    final pieces = <String>[];
    var start = 0;
    while (start < runes.length) {
      var end = start + maxChars;
      if (end > runes.length) end = runes.length;
      if (end < runes.length) {
        // Prefer a sentence end in the latter half of the slice. Searching
        // backwards avoids chopping a sentence right before a full stop.
        final minimumBreak = start + (maxChars * 0.55).floor();
        for (var index = end - 1; index >= minimumBreak; index--) {
          final rune = runes[index];
          if (_sentenceEndRunes.contains(rune)) {
            end = index + 1;
            break;
          }
        }
      }
      final piece = String.fromCharCodes(runes.sublist(start, end)).trim();
      if (piece.isNotEmpty) pieces.add(piece);
      start = end;
    }
    return pieces;
  }

  static const Set<int> _sentenceEndRunes = {
    0x3002, // 。
    0xFF01, // ！
    0xFF1F, // ？
    0xFF1B, // ；
    0x002E, // .
    0x0021, // !
    0x003F, // ?
    0x003B, // ;
    0x2026, // …
  };
}
