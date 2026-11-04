/// Where a reader left off in a book, persisted so the shelf can offer
/// "continue reading" at any time.
///
/// [chapterFraction] stores the position inside the current chapter (0 at the
/// top / first page, 1 at the end), so reopening a long chapter returns to the
/// same paragraph instead of restarting it.
class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.chapterCount,
    required this.updatedAt,
    this.chapterFraction = 0,
    this.readingSeconds = 0,
  });

  final String bookId;
  final int chapterIndex;
  final int chapterCount;
  final DateTime updatedAt;
  final double chapterFraction;

  /// Total time spent reading this book, accumulated by the reader.
  final int readingSeconds;

  double get safeChapterFraction => chapterFraction.clamp(0.0, 1.0);

  /// Whole-book position, clamped to 0..1.
  double get fraction {
    if (chapterCount <= 0) return 0;
    final position = chapterIndex.clamp(0, chapterCount - 1);
    return ((position + safeChapterFraction) / chapterCount).clamp(0.0, 1.0);
  }

  int get percent => (fraction * 100).round();

  bool get isFinished =>
      chapterCount > 0 &&
      chapterIndex >= chapterCount - 1 &&
      safeChapterFraction >= 0.995;

  String get label {
    if (chapterCount <= 0) return '未读';
    if (isFinished) return '已读完';
    return '读到第 ${chapterIndex + 1} 章 · $percent%';
  }

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    'chapterFraction': safeChapterFraction,
    'readingSeconds': readingSeconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ReadingProgress.fromJson(Map<String, Object?> json) {
    return ReadingProgress(
      bookId: json['bookId'] as String? ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
      chapterFraction: ((json['chapterFraction'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0),
      readingSeconds: (json['readingSeconds'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  ReadingProgress copyWith({
    String? bookId,
    int? chapterIndex,
    int? chapterCount,
    DateTime? updatedAt,
    double? chapterFraction,
    int? readingSeconds,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterCount: chapterCount ?? this.chapterCount,
      updatedAt: updatedAt ?? this.updatedAt,
      chapterFraction: chapterFraction ?? this.chapterFraction,
      readingSeconds: readingSeconds ?? this.readingSeconds,
    );
  }
}
