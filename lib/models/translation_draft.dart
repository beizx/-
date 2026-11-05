import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One chunk that already translated successfully.
///
/// [hash] is the source text fingerprint. If the chapter is edited, a mismatch
/// forces that chunk to be translated again instead of reusing a stale line.
class SavedChunk {
  const SavedChunk({required this.hash, required this.text});

  final String hash;
  final String text;

  Map<String, Object?> toJson() => {'hash': hash, 'text': text};

  factory SavedChunk.fromJson(Map<String, Object?> json) {
    return SavedChunk(
      hash: json['hash'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

/// Chunk-level progress for one book and one target language.
///
/// A full [TranslationRecord] is written only when every chunk succeeds.
/// This draft is what makes cancel, crash and failed-chunk retry resumable.
class TranslationDraft {
  const TranslationDraft({
    required this.bookId,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.providerId,
    required this.updatedAt,
    required this.totalChunks,
    required this.chunks,
    required this.failedKeys,
  });

  final String bookId;
  final String sourceLanguage;
  final String targetLanguage;
  final String providerId;
  final DateTime updatedAt;
  final int totalChunks;

  /// Keyed by [keyFor]: chapter id + chunk index.
  final Map<String, SavedChunk> chunks;

  /// Chunks that exhausted retries. They are absent from [chunks].
  final List<String> failedKeys;

  int get succeeded => chunks.length;

  int get failedChunks => failedKeys.length;

  int get remainingChunks {
    final left = totalChunks - succeeded - failedChunks;
    return left < 0 ? 0 : left;
  }

  bool get hasWorkRemaining => failedChunks > 0 || succeeded < totalChunks;

  /// Every chunk has been attempted and at least one is still failing.
  bool get onlyFailuresRemain =>
      failedChunks > 0 && succeeded + failedChunks >= totalChunks;

  static String keyFor(String chapterId, int chunkIndex) =>
      '$chapterId#$chunkIndex';

  static String fingerprint(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'providerId': providerId,
    'updatedAt': updatedAt.toIso8601String(),
    'totalChunks': totalChunks,
    'chunks': chunks.map((key, value) => MapEntry(key, value.toJson())),
    'failedKeys': failedKeys,
  };

  factory TranslationDraft.fromJson(Map<String, Object?> json) {
    final chunks = <String, SavedChunk>{};
    final rawChunks = json['chunks'];
    if (rawChunks is Map) {
      for (final entry in rawChunks.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final saved = SavedChunk.fromJson(Map<String, Object?>.from(value));
        if (saved.hash.isEmpty) continue;
        chunks[entry.key.toString()] = saved;
      }
    }
    final failed = <String>[];
    final rawFailed = json['failedKeys'];
    if (rawFailed is List) {
      for (final item in rawFailed) {
        if (item is String && item.isNotEmpty && !chunks.containsKey(item)) {
          failed.add(item);
        }
      }
    }
    return TranslationDraft(
      bookId: json['bookId'] as String? ?? '',
      sourceLanguage: json['sourceLanguage'] as String? ?? 'auto',
      targetLanguage: json['targetLanguage'] as String? ?? 'zh',
      providerId: json['providerId'] as String? ?? 'youdao',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      totalChunks: (json['totalChunks'] as num?)?.toInt() ?? chunks.length,
      chunks: chunks,
      failedKeys: failed,
    );
  }
}
