import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/utils/id_generator.dart';
import '../../core/utils/text_utils.dart';
import '../../models/book.dart';

/// Extracts readable text chapters from an EPUB archive.
///
/// Images, styling, footnote navigation and DRM are intentionally out of
/// scope: the output is a clean text-first book that can be translated and
/// re-exported.
abstract final class EpubParser {
  static Book parse({
    required Uint8List bytes,
    required String fileName,
    String? bookId,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw FormatException('EPUB 压缩包无法读取：$error');
    }

    final entries = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final path = _normalizeArchivePath(file.name);
      entries[path] = file;
      entries.putIfAbsent(path.toLowerCase(), () => file);
    }

    final containerFile = _findEntry(entries, 'META-INF/container.xml');
    if (containerFile == null) {
      throw const FormatException('EPUB 缺少 META-INF/container.xml');
    }

    final XmlDocument container;
    try {
      container = XmlDocument.parse(_readArchiveText(containerFile));
    } on XmlException catch (error) {
      throw FormatException('EPUB container.xml 格式错误：$error');
    }

    final rootfile = _firstElement(container.rootElement, 'rootfile');
    final opfPath = _decodeHref(rootfile?.getAttribute('full-path') ?? '');
    if (opfPath.isEmpty) {
      throw const FormatException('EPUB 未声明内容清单（OPF）');
    }

    final opfFile = _findEntry(entries, opfPath);
    if (opfFile == null) {
      throw FormatException('找不到 EPUB 内容清单：$opfPath');
    }

    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(_readArchiveText(opfFile));
    } on XmlException catch (error) {
      throw FormatException('EPUB OPF 格式错误：$error');
    }

    final metadata = _firstElement(opf.rootElement, 'metadata');
    final title = _firstText(metadata, 'title') ?? _titleFromFileName(fileName);
    final authors = _allTexts(metadata, 'creator');
    final author = authors.isEmpty ? '未知作者' : authors.take(2).join(' / ');

    final manifest = <String, _ManifestItem>{};
    final manifestElement = _firstElement(opf.rootElement, 'manifest');
    if (manifestElement != null) {
      for (final element in _descendantsNamed(manifestElement, 'item')) {
        final id = element.getAttribute('id');
        final href = element.getAttribute('href');
        if (id == null || href == null || href.isEmpty) continue;
        manifest[id] = _ManifestItem(
          id: id,
          href: href,
          mediaType: element.getAttribute('media-type') ?? '',
          properties: element.getAttribute('properties') ?? '',
        );
      }
    }

    final opfDirectory = p.posix.dirname(opfPath);
    final spine = <_ManifestItem>[];
    final spineElement = _firstElement(opf.rootElement, 'spine');
    if (spineElement != null) {
      for (final itemref in _descendantsNamed(spineElement, 'itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref == null) continue;
        final item = manifest[idref];
        if (item == null) continue;
        if (item.properties.split(RegExp(r'\s+')).contains('nav')) continue;
        final mediaType = item.mediaType.toLowerCase();
        if (mediaType.isNotEmpty &&
            mediaType != 'application/xhtml+xml' &&
            mediaType != 'text/html') {
          continue;
        }
        spine.add(item);
      }
    }

    if (spine.isEmpty) {
      // Some malformed EPUBs don't have a usable spine. Fall back to manifest
      // reading order rather than rejecting an otherwise readable book.
      spine.addAll(
        manifest.values.where((item) {
          final mediaType = item.mediaType.toLowerCase();
          return mediaType == 'application/xhtml+xml' ||
              mediaType == 'text/html' ||
              item.href.toLowerCase().endsWith('.xhtml') ||
              item.href.toLowerCase().endsWith('.html');
        }),
      );
    }

    final chapters = <BookChapter>[];
    for (final item in spine) {
      final itemPath = _resolveHref(opfDirectory, item.href);
      final file = _findEntry(entries, itemPath);
      if (file == null) continue;
      final source = _readArchiveText(file);
      final extracted = _chapterFromHtml(source, chapters.length + 1);
      if (extracted == null) continue;
      final chapterIndex = chapters.length;
      chapters.add(
        BookChapter(
          id: 'chapter_$chapterIndex',
          index: chapterIndex,
          title: extracted.title,
          text: extracted.text,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const FormatException('EPUB 中没有找到可翻译的文本章节');
    }

    final id = bookId ?? generateId('book_');
    final charCount = chapters.fold<int>(
      0,
      (sum, chapter) => sum + countVisibleCharacters(chapter.text),
    );

    return Book(
      meta: BookMeta(
        id: id,
        title: title.trim().isEmpty
            ? _titleFromFileName(fileName)
            : title.trim(),
        author: author.trim(),
        fileName: fileName,
        format: BookFormat.epub,
        chapterCount: chapters.length,
        charCount: charCount,
        importedAt: DateTime.now(),
      ),
      chapters: chapters,
    );
  }

  static _ExtractedChapter? _chapterFromHtml(String source, int position) {
    final dom.Document document;
    try {
      document = html_parser.parse(source);
    } on Object {
      return null;
    }

    final body = document.body;
    if (body == null) return null;

    final headingText = _normalizedInline(
      document.querySelector('h1, h2, h3')?.text ?? '',
    );
    final docTitle = _normalizedInline(
      document.querySelector('title')?.text ?? '',
    );
    var title = headingText.isNotEmpty && headingText.length <= 80
        ? headingText
        : docTitle.isNotEmpty && docTitle.length <= 80
        ? docTitle
        : '第 $position 章';

    final buffer = StringBuffer();

    void walk(dom.Node node) {
      if (node is dom.Text) {
        final value = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (value.isNotEmpty) buffer.write(value);
        return;
      }
      if (node is! dom.Element) return;

      final tag = node.localName?.toLowerCase() ?? '';
      if (_skippedTags.contains(tag)) return;
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }

      final isBlock = _blockTags.contains(tag);
      if (isBlock) buffer.write('\n\n');
      for (final child in node.nodes) {
        walk(child);
      }
      if (isBlock) buffer.write('\n\n');
    }

    walk(body);
    var text = _normalizeBlocks(buffer.toString());
    if (text.isEmpty) return null;

    // Many EPUB chapters repeat the heading as the first body line. The
    // reader already renders the title, so remove an exact duplicate.
    final firstLine = text.split('\n').first.trim();
    if (title.isNotEmpty && firstLine == title) {
      text = text.substring(firstLine.length).trimLeft();
    }

    if (text.runes.length < 2) return null;
    if (title.trim().isEmpty) title = '第 $position 章';
    return _ExtractedChapter(title, text);
  }

  static const Set<String> _skippedTags = {
    'script',
    'style',
    'noscript',
    'svg',
    'img',
    'rt',
    'rp',
    'nav',
  };

  static const Set<String> _blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'div',
    'figcaption',
    'figure',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tr',
    'ul',
  };

  static String _normalizeBlocks(String raw) {
    final lines = raw
        .replaceAll('\u00A0', ' ')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .toList();
    final output = <String>[];
    for (final line in lines) {
      if (line.isEmpty) {
        if (output.isNotEmpty && output.last.isNotEmpty) output.add('');
      } else {
        output.add(line);
      }
    }
    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }
    return output.join('\n').trim();
  }

  static String _readArchiveText(ArchiveFile file) {
    final bytes = file.readBytes() ?? Uint8List(0);
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return text;
  }

  static ArchiveFile? _findEntry(
    Map<String, ArchiveFile> entries,
    String path,
  ) {
    final normalized = _normalizeArchivePath(path);
    return entries[normalized] ?? entries[normalized.toLowerCase()];
  }

  static String _normalizeArchivePath(String path) {
    return path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  static String _decodeHref(String href) {
    final withoutFragment = href.split('#').first.split('?').first;
    try {
      return Uri.decodeComponent(withoutFragment);
    } on ArgumentError {
      return withoutFragment;
    }
  }

  static String _resolveHref(String baseDirectory, String href) {
    final decoded = _decodeHref(href);
    final joined = p.posix.normalize(p.posix.join(baseDirectory, decoded));
    return _normalizeArchivePath(joined);
  }

  static String _titleFromFileName(String fileName) {
    final baseName = fileName.split(RegExp(r'[/\\]')).last;
    final dot = baseName.lastIndexOf('.');
    final title = (dot == -1 ? baseName : baseName.substring(0, dot)).trim();
    return title.isEmpty ? '未命名书籍' : title;
  }

  static String _normalizedInline(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static XmlElement? _firstElement(XmlElement root, String localName) {
    for (final element in _descendantsNamed(root, localName)) {
      return element;
    }
    return null;
  }

  static Iterable<XmlElement> _descendantsNamed(
    XmlElement root,
    String localName,
  ) sync* {
    for (final child in root.children.whereType<XmlElement>()) {
      if (child.name.local == localName) yield child;
      yield* _descendantsNamed(child, localName);
    }
  }

  static String? _firstText(XmlElement? root, String localName) {
    if (root == null) return null;
    for (final element in _descendantsNamed(root, localName)) {
      final value = element.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static List<String> _allTexts(XmlElement? root, String localName) {
    if (root == null) return const [];
    return [
      for (final element in _descendantsNamed(root, localName))
        if (element.innerText.replaceAll(RegExp(r'\s+'), ' ').trim()
            case final value when value.isNotEmpty)
          value,
    ];
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String href;
  final String mediaType;
  final String properties;
}

class _ExtractedChapter {
  const _ExtractedChapter(this.title, this.text);

  final String title;
  final String text;
}
