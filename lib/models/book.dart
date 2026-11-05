import 'language.dart';

/// Supported input document formats.
enum BookFormat {
  txt('TXT', 'txt'),
  epub('EPUB', 'epub');

  const BookFormat(this.label, this.extension);

  final String label;
  final String extension;

  static BookFormat fromExtension(String extension) {
    return switch (extension.toLowerCase().replaceFirst('.', '')) {
      'epub' => BookFormat.epub,
      _ => BookFormat.txt,
    };
  }

  static BookFormat fromName(String? name) {
    if (name == null) return BookFormat.txt;
    final dot = name.lastIndexOf('.');
    return fromExtension(dot == -1 ? 'txt' : name.substring(dot + 1));
  }
}

/// Lightweight book information used by the library list.
class BookMeta {
  const BookMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.fileName,
    required this.format,
    required this.chapterCount,
    required this.charCount,
    required this.importedAt,
  });

  final String id;
  final String title;
  final String author;
  final String fileName;
  final BookFormat format;
  final int chapterCount;
  final int charCount;
  final DateTime importedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'fileName': fileName,
    'format': format.name,
    'chapterCount': chapterCount,
    'charCount': charCount,
    'importedAt': importedAt.toIso8601String(),
  };

  factory BookMeta.fromJson(Map<String, Object?> json) {
    return BookMeta(
      id: json['id'] as String,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : '未命名书籍',
      author: (json['author'] as String?)?.trim().isNotEmpty == true
          ? json['author'] as String
          : '未知作者',
      fileName: json['fileName'] as String? ?? '',
      format: json['format'] == 'epub' ? BookFormat.epub : BookFormat.txt,
      chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
      charCount: (json['charCount'] as num?)?.toInt() ?? 0,
      importedAt:
          DateTime.tryParse(json['importedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class BookChapter {
  const BookChapter({
    required this.id,
    required this.index,
    required this.title,
    required this.text,
  });

  final String id;
  final int index;
  final String title;
  final String text;

  int get charCount => text.runes.length;

  Map<String, Object?> toJson() => {
    'id': id,
    'index': index,
    'title': title,
    'text': text,
  };

  factory BookChapter.fromJson(Map<String, Object?> json) {
    return BookChapter(
      id: json['id'] as String? ?? 'chapter_0',
      index: (json['index'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '正文',
      text: json['text'] as String? ?? '',
    );
  }
}

/// A fully parsed book. The [meta] summary is persisted separately from the
/// chapter body so the library can load quickly.
class Book {
  const Book({required this.meta, required this.chapters});

  final BookMeta meta;
  final List<BookChapter> chapters;

  String get id => meta.id;
  String get title => meta.title;
  String get author => meta.author;
  int get charCount => meta.charCount;

  Map<String, Object?> toJson() => {
    'meta': meta.toJson(),
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
  };

  factory Book.fromJson(Map<String, Object?> json) {
    final metaJson = json['meta'];
    final chaptersJson = json['chapters'];
    if (metaJson is! Map) {
      throw const FormatException('书籍数据缺少元信息');
    }
    final chapters = <BookChapter>[];
    if (chaptersJson is List) {
      for (final item in chaptersJson.whereType<Map>()) {
        chapters.add(BookChapter.fromJson(Map<String, Object?>.from(item)));
      }
    }
    final meta = BookMeta.fromJson(Map<String, Object?>.from(metaJson));
    return Book(meta: meta, chapters: chapters);
  }

  Book copyWith({BookMeta? meta, List<BookChapter>? chapters}) {
    return Book(meta: meta ?? this.meta, chapters: chapters ?? this.chapters);
  }
}

/// A parsed, translated chapter kept in [TranslationRecord].
class TranslatedChapter {
  const TranslatedChapter({
    required this.chapterId,
    required this.chapterIndex,
    required this.title,
    required this.text,
  });

  final String chapterId;
  final int chapterIndex;
  final String title;
  final String text;

  Map<String, Object?> toJson() => {
    'chapterId': chapterId,
    'chapterIndex': chapterIndex,
    'title': title,
    'text': text,
  };

  factory TranslatedChapter.fromJson(Map<String, Object?> json) {
    return TranslatedChapter(
      chapterId: json['chapterId'] as String? ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '正文',
      text: json['text'] as String? ?? '',
    );
  }
}

class TranslationRecord {
  const TranslationRecord({
    required this.bookId,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.providerId,
    required this.createdAt,
    required this.chapters,
    this.complete = true,
  });

  final String bookId;
  final String sourceLanguage;
  final String targetLanguage;
  final String providerId;
  final DateTime createdAt;
  final List<TranslatedChapter> chapters;

  /// False while some chapters are still missing. Old files omit the field
  /// and are treated as finished translations.
  final bool complete;

  AppLanguage get target => Languages.byCode(targetLanguage);
  AppLanguage get source =>
      Languages.byCode(sourceLanguage, fallback: Languages.auto);

  TranslatedChapter? chapterFor(String chapterId) {
    for (final chapter in chapters) {
      if (chapter.chapterId == chapterId) return chapter;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'providerId': providerId,
    'createdAt': createdAt.toIso8601String(),
    'complete': complete,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
  };

  factory TranslationRecord.fromJson(Map<String, Object?> json) {
    final chapters = <TranslatedChapter>[];
    final rawChapters = json['chapters'];
    if (rawChapters is List) {
      for (final item in rawChapters.whereType<Map>()) {
        chapters.add(
          TranslatedChapter.fromJson(Map<String, Object?>.from(item)),
        );
      }
    }
    return TranslationRecord(
      bookId: json['bookId'] as String? ?? '',
      sourceLanguage: json['sourceLanguage'] as String? ?? 'auto',
      targetLanguage: json['targetLanguage'] as String? ?? 'zh',
      providerId: json['providerId'] as String? ?? 'youdao',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      chapters: chapters,
      complete: json['complete'] is bool ? json['complete'] as bool : true,
    );
  }
}
