/// Normalize line endings without touching paragraph content.
String normalizeLineEndings(String text) {
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Remove a UTF-8 BOM and surrounding whitespace from imported text.
String cleanImportedText(String text) {
  var result = normalizeLineEndings(text);
  if (result.startsWith('\uFEFF')) {
    result = result.substring(1);
  }
  return result.trim();
}

/// Count visible characters (code points), excluding whitespace.
int countVisibleCharacters(String text) {
  return text.runes.where((rune) {
    return String.fromCharCode(rune).trim().isNotEmpty;
  }).length;
}

String formatCharacterCount(int count) {
  if (count >= 10000) {
    final value = count / 10000;
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} 万';
  }
  return count.toString();
}

String formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}.$month.$day';
}

String formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatDate(date)} $hour:$minute';
}

/// Make a user-facing file name safe across Android and iOS file providers.
String sanitizeFileName(String name, {String fallback = '译文'}) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return fallback;
  if (cleaned.length <= 80) return cleaned;
  return cleaned.substring(0, 80);
}

/// A human-friendly duration used in the API test result.
String formatLatency(Duration duration) {
  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds} 毫秒';
  }
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} 秒';
}

/// Accumulated reading time, shown on the book detail page and shelf.
String formatReadingDuration(int seconds) {
  if (seconds <= 0) return '还没开始计时';
  if (seconds < 60) return '不到 1 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}

/// 24-hour wall clock used by the reader's bottom indicator.
String formatClockTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Brief excerpt for bookmarks and search results.
String excerpt(String text, {int maxLength = 72}) {
  final flattened = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flattened.length <= maxLength) return flattened;
  return '${flattened.substring(0, maxLength)}…';
}
