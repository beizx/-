import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/utils/text_utils.dart';
import '../models/book.dart';

/// Pure builders for the two export formats. Kept free of Flutter and file I/O
/// so they can be tested directly.
abstract final class DocumentExporter {
  static String buildBookTxt(Book book) {
    final buffer = StringBuffer()
      ..writeln(book.title)
      ..writeln('作者：${book.author}')
      ..writeln('内容：去重后的本地书籍')
      ..writeln('生成时间：${formatDateTime(DateTime.now())}')
      ..writeln()
      ..writeln('· 本文件由「Beizx的阅读器」生成 ·')
      ..writeln();

    for (final chapter in book.chapters) {
      buffer
        ..writeln('— ${chapter.title} —')
        ..writeln()
        ..writeln(chapter.text)
        ..writeln();
    }
    return buffer.toString();
  }

  static Uint8List buildBookEpub(Book book, {required String languageCode}) {
    return buildEpub(
      book,
      TranslationRecord(
        bookId: book.id,
        sourceLanguage: 'auto',
        targetLanguage: languageCode,
        providerId: 'local-dedupe',
        createdAt: DateTime.now(),
        chapters: book.chapters
            .map(
              (chapter) => TranslatedChapter(
                chapterId: chapter.id,
                chapterIndex: chapter.index,
                title: chapter.title,
                text: chapter.text,
              ),
            )
            .toList(growable: false),
      ),
      languageOverride: languageCode,
      description: '由「Beizx的阅读器」多语去重导出的本地书籍',
    );
  }

  static String buildTxt(Book book, TranslationRecord record) {
    final buffer = StringBuffer()
      ..writeln(book.title)
      ..writeln('作者：${book.author}')
      ..writeln('翻译：${record.source.label} → ${record.target.label}')
      ..writeln('导出时间：${formatDateTime(DateTime.now())}')
      ..writeln()
      ..writeln('· 本文件由「Beizx的阅读器」生成 ·')
      ..writeln();

    for (final chapter in record.chapters) {
      buffer
        ..writeln('— ${chapter.title} —')
        ..writeln()
        ..writeln(chapter.text)
        ..writeln();
    }
    return buffer.toString();
  }

  static Uint8List buildEpub(
    Book book,
    TranslationRecord record, {
    String? languageOverride,
    String? description,
  }) {
    final archive = Archive();
    final identifier = 'urn:uuid:${_uuidLike()}';
    final modified = DateTime.now().toUtc().toIso8601String();
    final safeTitle = _escapeXml(book.title);
    final safeAuthor = _escapeXml(book.author);
    final language = languageOverride ?? record.target.code;
    final mimetypeBytes = utf8.encode('application/epub+zip');

    archive.addFile(
      ArchiveFile.noCompress('mimetype', mimetypeBytes.length, mimetypeBytes),
    );

    archive.addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''',
      ),
    );

    final manifest = StringBuffer();
    final spine = StringBuffer();
    final navItems = StringBuffer();

    for (var index = 0; index < record.chapters.length; index++) {
      final chapter = record.chapters[index];
      final number = index + 1;
      final href = 'chapters/chapter_$number.xhtml';
      final chapterTitle = _escapeXml(chapter.title);
      manifest.writeln(
        '    <item id="chapter_$number" href="$href" media-type="application/xhtml+xml"/>',
      );
      spine.writeln('    <itemref idref="chapter_$number"/>');
      navItems.writeln('      <li><a href="$href">$chapterTitle</a></li>');

      final paragraphs = chapter.text
          .split(RegExp(r'\n+'))
          .map((paragraph) => paragraph.trim())
          .where((paragraph) => paragraph.isNotEmpty)
          .map((paragraph) => '      <p>${_escapeXml(paragraph)}</p>')
          .join('\n');

      archive.addFile(
        ArchiveFile.string(
          'OEBPS/$href',
          '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$language" lang="$language">
  <head>
    <meta charset="UTF-8"/>
    <title>$chapterTitle</title>
    <link rel="stylesheet" type="text/css" href="../styles/book.css"/>
  </head>
  <body>
    <section epub:type="chapter" xmlns:epub="http://www.idpf.org/2007/ops">
      <h1>$chapterTitle</h1>
$paragraphs
    </section>
  </body>
</html>
''',
        ),
      );
    }

    archive.addFile(
      ArchiveFile.string('OEBPS/styles/book.css', '''@charset "UTF-8";
html, body { margin: 0; padding: 0; }
body {
  font-family: serif;
  line-height: 1.85;
  color: #24211B;
  background: #FFFCF5;
  padding: 1.4em;
}
h1 { font-size: 1.35em; margin: 0 0 1.4em; }
p { margin: 0 0 0.85em; text-indent: 1.6em; }
'''),
    );

    archive.addFile(
      ArchiveFile.string(
        'OEBPS/nav.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language" lang="$language">
  <head><meta charset="UTF-8"/><title>$safeTitle</title></head>
  <body>
    <nav epub:type="toc" id="toc">
      <h1>目录</h1>
      <ol>
$navItems      </ol>
    </nav>
  </body>
</html>
''',
      ),
    );

    archive.addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">$identifier</dc:identifier>
    <dc:title>$safeTitle</dc:title>
    <dc:creator>$safeAuthor</dc:creator>
    <dc:language>$language</dc:language>
    <dc:description>${_escapeXml(description ?? '由「Beizx的阅读器」从 ${book.meta.format.label} 翻译导出')}</dc:description>
    <meta property="dcterms:modified">$modified</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="css" href="styles/book.css" media-type="text/css"/>
$manifest  </manifest>
  <spine>
$spine  </spine>
</package>
''',
      ),
    );

    return ZipEncoder().encodeBytes(archive);
  }

  static String exportFileName(
    Book book,
    TranslationRecord record,
    String ext,
  ) {
    final title = sanitizeFileName(book.title, fallback: '译文');
    return '${title}_译文_${record.target.code}.$ext';
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _uuidLike() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final raw = (now.toRadixString(16) + (now >> 7).toRadixString(16))
        .padRight(32, '0')
        .substring(0, 32);
    return '${raw.substring(0, 8)}-${raw.substring(8, 12)}-'
        '${raw.substring(12, 16)}-${raw.substring(16, 20)}-'
        '${raw.substring(20, 32)}';
  }
}
