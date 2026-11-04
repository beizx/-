import '../core/utils/id_generator.dart';

/// A saved spot inside a chapter. Bookmarks are local, per book, and store a
/// short excerpt so the list is readable without reopening the chapter.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.fraction,
    required this.snippet,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;

  /// Position inside the chapter, 0..1.
  final double fraction;
  final String snippet;
  final DateTime createdAt;

  factory Bookmark.create({
    required String bookId,
    required int chapterIndex,
    required String chapterTitle,
    required double fraction,
    required String snippet,
    DateTime? createdAt,
  }) {
    final timestamp = createdAt ?? DateTime.now();
    return Bookmark(
      id: generateId('bm_${timestamp.millisecondsSinceEpoch}_'),
      bookId: bookId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      fraction: fraction.clamp(0.0, 1.0),
      snippet: snippet.trim(),
      createdAt: timestamp,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'bookId': bookId,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'fraction': fraction,
    'snippet': snippet,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, Object?> json) {
    return Bookmark(
      id: json['id'] as String? ?? generateId('bm_'),
      bookId: json['bookId'] as String? ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterTitle: json['chapterTitle'] as String? ?? '',
      fraction: ((json['fraction'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      snippet: json['snippet'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
