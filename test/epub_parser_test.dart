import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/services/import/epub_parser.dart';

Uint8List buildTestEpub() {
  final archive = Archive();
  final mimetype = utf8.encode('application/epub+zip');
  archive.addFile(
    ArchiveFile.noCompress('mimetype', mimetype.length, mimetype),
  );
  archive.addFile(
    ArchiveFile.string(
      'META-INF/container.xml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
    ),
  );
  archive.addFile(
    ArchiveFile.string(
      'OEBPS/content.opf',
      '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>星河旅人</dc:title>
    <dc:creator>林川</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>''',
    ),
  );
  archive.addFile(
    ArchiveFile.string(
      'OEBPS/nav.xhtml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><ol>
<li><a href="text/chapter1.xhtml">目录项一</a></li>
</ol></nav></body></html>''',
    ),
  );
  archive.addFile(
    ArchiveFile.string(
      'OEBPS/text/chapter1.xhtml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章 夜航</title></head>
<body>
  <h1>第一章 夜航</h1>
  <p>风从舷窗掠过。</p>
  <p>他把 <em>灯</em> 点亮 &amp; 等待黎明。</p>
  <script>shouldNotAppear()</script>
</body></html>''',
    ),
  );
  archive.addFile(
    ArchiveFile.string(
      'OEBPS/text/chapter2.xhtml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章 灯火</title></head>
<body>
  <h2>第二章 灯火</h2>
  <p>城市在雾里浮沉。</p>
  <p>她翻开那本旧书。</p>
</body></html>''',
    ),
  );
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('EpubParser', () {
    test('reads OPF metadata and spine chapters', () {
      final book = EpubParser.parse(
        bytes: buildTestEpub(),
        fileName: '星河旅人.epub',
      );

      expect(book.title, '星河旅人');
      expect(book.author, '林川');
      expect(book.meta.format.name, 'epub');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].title, '第一章 夜航');
      expect(book.chapters[1].title, '第二章 灯火');
      expect(book.chapters[0].text, contains('风从舷窗掠过。'));
      expect(book.chapters[0].text, contains('灯'));
      expect(book.chapters[0].text, contains('&'));
      expect(book.chapters[0].text, isNot(contains('shouldNotAppear')));
      // Heading duplicates used as reader titles are removed from the body.
      expect(book.chapters[0].text, isNot(startsWith('第一章')));
    });

    test('does not include the navigation document', () {
      final book = EpubParser.parse(
        bytes: buildTestEpub(),
        fileName: '星河旅人.epub',
      );
      expect(
        book.chapters.any((chapter) => chapter.text.contains('目录项一')),
        isFalse,
      );
    });

    test('rejects an unreadable archive', () {
      expect(
        () => EpubParser.parse(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          fileName: 'broken.epub',
        ),
        throwsFormatException,
      );
    });
  });
}
