import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/reading_progress.dart';

void main() {
  group('ReadingProgress', () {
    test('reports chapter and in-chapter progress', () {
      final progress = ReadingProgress(
        bookId: 'book_1',
        chapterIndex: 1,
        chapterCount: 5,
        updatedAt: DateTime(2026, 11, 4),
      );

      expect(progress.percent, 20);
      expect(progress.label, '读到第 2 章 · 20%');
      expect(progress.isFinished, isFalse);

      final halfway = progress.copyWith(chapterFraction: 0.5);
      expect(halfway.fraction, closeTo(0.3, 0.0001));
      expect(halfway.percent, 30);
      expect(halfway.label, '读到第 2 章 · 30%');
    });

    test('serializes and restores reading position and reading time', () {
      final progress = ReadingProgress(
        bookId: 'book_2',
        chapterIndex: 3,
        chapterCount: 4,
        chapterFraction: 1,
        readingSeconds: 3720,
        updatedAt: DateTime(2026, 11, 4, 12),
      );

      final restored = ReadingProgress.fromJson(progress.toJson());
      expect(restored.bookId, progress.bookId);
      expect(restored.chapterIndex, progress.chapterIndex);
      expect(restored.chapterCount, progress.chapterCount);
      expect(restored.chapterFraction, 1);
      expect(restored.readingSeconds, 3720);
      expect(restored.updatedAt, progress.updatedAt);
      expect(restored.isFinished, isTrue);
      expect(restored.label, '已读完');
    });

    test('clamps progress to the chapter bounds', () {
      final clamped = ReadingProgress(
        bookId: 'book_3',
        chapterIndex: 8,
        chapterCount: 5,
        chapterFraction: 1,
        updatedAt: DateTime(2026, 11, 4),
      );
      expect(clamped.percent, 100);
      expect(clamped.isFinished, isTrue);

      final negative = ReadingProgress(
        bookId: 'book_4',
        chapterIndex: -2,
        chapterCount: 5,
        chapterFraction: 0.5,
        updatedAt: DateTime(2026, 11, 4),
      );
      expect(negative.fraction, 0.1);
      expect(negative.percent, 10);
    });

    test('tolerates legacy JSON without the new fields', () {
      final legacy = ReadingProgress.fromJson({
        'bookId': 'book_5',
        'chapterIndex': 1,
        'chapterCount': 5,
        'updatedAt': '2026-11-04T10:00:00.000',
      });
      expect(legacy.chapterFraction, 0);
      expect(legacy.readingSeconds, 0);
      expect(legacy.percent, 20);
    });
  });
}
