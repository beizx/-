import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/services/document_exporter.dart';
import 'package:translation_app/services/import/epub_parser.dart';

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_test',
      title: '雾中灯塔',
      author: '林川',
      fileName: '雾中灯塔.epub',
      format: BookFormat.epub,
      chapterCount: 2,
      charCount: 100,
      importedAt: DateTime(2026, 11, 1),
    ),
    chapters: const [
      BookChapter(
        id: 'chapter_0',
        index: 0,
        title: '第一章 起雾',
        text: '海面起了雾。\n\n灯塔仍亮着。',
      ),
      BookChapter(id: 'chapter_1', index: 1, title: '第二章 归航', text: '船在清晨靠岸。'),
    ],
  );
}

Book _dedupedBook() {
  return Book(
    meta: BookMeta(
      id: 'book_deduped',
      title: '雾中灯塔（中文去重版）',
      author: '林川',
      fileName: '雾中灯塔.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 20,
      importedAt: DateTime(2026, 11, 4),
    ),
    chapters: const [
      BookChapter(
        id: 'chapter_0',
        index: 0,
        title: '第一章 起雾',
        text: '海面起了雾。\n灯塔仍亮着。',
      ),
      BookChapter(id: 'chapter_1', index: 1, title: '第二章 归航', text: '船在清晨靠岸。'),
    ],
  );
}

TranslationRecord _record() {
  return TranslationRecord(
    bookId: 'book_test',
    sourceLanguage: 'zh',
    targetLanguage: Languages.ja.code,
    providerId: 'youdao',
    createdAt: DateTime(2026, 11, 4, 10, 30),
    chapters: const [
      TranslatedChapter(
        chapterId: 'chapter_0',
        chapterIndex: 0,
        title: '第一章 起雾',
        text: '海面に霧が立ちこめた。\n\n灯台はまだ灯っている。',
      ),
      TranslatedChapter(
        chapterId: 'chapter_1',
        chapterIndex: 1,
        title: '第二章 归航',
        text: '船は早朝に岸へ着いた。',
      ),
    ],
  );
}

void main() {
  group('DocumentExporter', () {
    test('builds a readable TXT with metadata', () {
      final text = DocumentExporter.buildTxt(_book(), _record());
      expect(text, contains('雾中灯塔'));
      expect(text, contains('中文 → 日语'));
      expect(text, contains('第一章 起雾'));
      expect(text, contains('海面に霧が立ちこめた。'));
    });

    test('builds a valid EPUB that can be parsed again', () {
      final bytes = DocumentExporter.buildEpub(_book(), _record());
      final archive = ZipDecoder().decodeBytes(bytes);

      expect(archive.files.first.name, 'mimetype');
      expect(utf8.decode(archive.files.first.content), 'application/epub+zip');
      expect(archive.files.first.compression, CompressionType.none);

      final parsed = EpubParser.parse(bytes: bytes, fileName: 'export.epub');
      expect(parsed.title, '雾中灯塔');
      expect(parsed.author, '林川');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters.first.text, contains('海面に霧が立ちこめた。'));
      expect(parsed.chapters.last.text, contains('船は早朝に岸へ着いた。'));
    });

    test('sanitizes export file names', () {
      final name = DocumentExporter.exportFileName(_book(), _record(), 'epub');
      expect(name, '雾中灯塔_译文_ja.epub');
      expect(name, isNot(contains('/')));
    });
  });

  group('DocumentExporter book export', () {
    test('builds a deduped TXT without translation metadata', () {
      final text = DocumentExporter.buildBookTxt(_dedupedBook());
      expect(text, contains('雾中灯塔（中文去重版）'));
      expect(text, contains('作者：林川'));
      expect(text, contains('第一章 起雾'));
      expect(text, contains('灯塔仍亮着。'));
      expect(text, isNot(contains('海面に霧が立ちこめた。')));
      expect(text, isNot(contains('→')));
    });

    test('builds a deduped EPUB that keeps the chosen language', () {
      final bytes = DocumentExporter.buildBookEpub(
        _dedupedBook(),
        languageCode: 'zh',
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.first.name, 'mimetype');

      final opf = utf8.decode(
        archive.files
            .firstWhere((file) => file.name == 'OEBPS/content.opf')
            .content,
      );
      expect(opf, contains('<dc:language>zh</dc:language>'));
      expect(opf, contains('多语去重'));

      final parsed = EpubParser.parse(bytes: bytes, fileName: 'dedupe.epub');
      expect(parsed.title, '雾中灯塔（中文去重版）');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters.first.text, contains('灯塔仍亮着。'));
    });
  });
}
