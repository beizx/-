import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/utils/text_utils.dart';
import '../models/book.dart';
import 'document_exporter.dart';
import 'local_store.dart';

enum ExportFormat { txt, epub }

class ExportService {
  ExportService(this.store);

  final LocalStore store;

  Future<File> writeExport({
    required Book book,
    required TranslationRecord record,
    required ExportFormat format,
  }) async {
    await store.exportsDirectory.create(recursive: true);
    final extension = format == ExportFormat.epub ? 'epub' : 'txt';
    final fileName = DocumentExporter.exportFileName(book, record, extension);
    final file = File(p.join(store.exportsDirectory.path, fileName));

    if (format == ExportFormat.epub) {
      final bytes = DocumentExporter.buildEpub(book, record);
      await file.writeAsBytes(bytes, flush: true);
    } else {
      final text = DocumentExporter.buildTxt(book, record);
      // A UTF-8 BOM keeps Chinese TXT readable in Windows Notepad.
      await file.writeAsBytes(const [0xEF, 0xBB, 0xBF], flush: false);
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    }
    return file;
  }

  Future<File> writeBookExport({
    required Book book,
    required ExportFormat format,
    String languageCode = 'zh',
  }) async {
    await store.exportsDirectory.create(recursive: true);
    final extension = format == ExportFormat.epub ? 'epub' : 'txt';
    final safeTitle = sanitizeFileName(book.title, fallback: '去重版');
    final file = File(
      p.join(store.exportsDirectory.path, '${safeTitle}_去重版.$extension'),
    );
    if (format == ExportFormat.epub) {
      await file.writeAsBytes(
        DocumentExporter.buildBookEpub(book, languageCode: languageCode),
        flush: true,
      );
    } else {
      await file.writeAsBytes(const [0xEF, 0xBB, 0xBF], flush: false);
      await file.writeAsString(
        DocumentExporter.buildBookTxt(book),
        mode: FileMode.append,
        flush: true,
      );
    }
    return file;
  }

  Future<File> shareBookExport({
    required Book book,
    required ExportFormat format,
    String languageCode = 'zh',
  }) async {
    final file = await writeBookExport(
      book: book,
      format: format,
      languageCode: languageCode,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: format == ExportFormat.epub
                ? 'application/epub+zip'
                : 'text/plain',
          ),
        ],
        subject: '${book.title} · 去重版',
        text: '由「Beizx的阅读器」生成的本地去重书籍。',
      ),
    );
    return file;
  }

  Future<File> shareExport({
    required Book book,
    required TranslationRecord record,
    required ExportFormat format,
  }) async {
    final file = await writeExport(book: book, record: record, format: format);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: format == ExportFormat.epub
                ? 'application/epub+zip'
                : 'text/plain',
          ),
        ],
        subject: '${book.title} · ${record.target.label}译文',
        text: '由「Beizx的阅读器」翻译导出的${record.target.label}版本。',
      ),
    );
    return file;
  }
}
