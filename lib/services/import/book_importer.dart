import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../models/book.dart';
import 'epub_parser.dart';
import 'txt_parser.dart';

class BookImportException implements Exception {
  const BookImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Picks and parses local TXT / EPUB files.
class BookImporter {
  static const int maxFileBytes = 80 * 1024 * 1024;

  /// Opens the native document picker. Returns `null` when the user cancels.
  Future<Book?> pickAndImport() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择要翻译的书籍',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub'],
    );
    if (file == null) return null;

    final fileName = file.name;
    final extension = _extensionOf(fileName);
    if (extension != 'txt' && extension != 'epub') {
      throw const BookImportException('目前仅支持 TXT 和 EPUB 文件');
    }

    final length = await file.length();
    if (length != null && length > maxFileBytes) {
      throw const BookImportException('文件超过 80 MB，请先拆分后再导入');
    }

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object catch (error) {
      throw BookImportException('读取文件失败：$error');
    }

    return importBytes(bytes: bytes, fileName: fileName);
  }

  /// Parse in a background isolate so large EPUBs do not freeze the UI.
  Future<Book> importBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw const BookImportException('文件是空的');
    }
    if (bytes.length > maxFileBytes) {
      throw const BookImportException('文件超过 80 MB，请先拆分后再导入');
    }

    final extension = _extensionOf(fileName);
    if (extension != 'txt' && extension != 'epub') {
      throw const BookImportException('目前仅支持 TXT 和 EPUB 文件');
    }

    try {
      return await Isolate.run(
        () =>
            parseBytes(bytes: bytes, fileName: fileName, extension: extension),
      );
    } on FormatException catch (error) {
      throw BookImportException(error.message);
    } on BookImportException {
      rethrow;
    } on Object catch (error) {
      throw BookImportException('解析文件失败：$error');
    }
  }

  /// Synchronous parser, useful for unit tests and isolate entry points.
  static Book parseBytes({
    required Uint8List bytes,
    required String fileName,
    required String extension,
  }) {
    return switch (extension) {
      'epub' => EpubParser.parse(bytes: bytes, fileName: fileName),
      _ => TxtParser.parse(bytes: bytes, fileName: fileName),
    };
  }

  static String _extensionOf(String fileName) {
    final baseName = fileName.split(RegExp(r'[/\\]')).last;
    final dot = baseName.lastIndexOf('.');
    return dot == -1 ? '' : baseName.substring(dot + 1).toLowerCase();
  }
}
