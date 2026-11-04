import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

/// Decodes the encodings commonly found in downloaded TXT novels.
///
/// Order: BOM-based UTF-8/UTF-16, strict UTF-8, near-valid UTF-8, GBK, then
/// a replacement-tolerant UTF-8 fallback so a file can still be opened.
String decodeBookBytes(Uint8List bytes) {
  if (bytes.isEmpty) return '';

  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }

  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), Endian.little);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), Endian.big);
  }

  try {
    return utf8.decode(bytes);
  } on FormatException {
    // A handful of broken bytes should not force a perfectly good UTF-8 file
    // through GBK decoding.
    final lenient = utf8.decode(bytes, allowMalformed: true);
    final broken = '\uFFFD'.allMatches(lenient).length;
    if (broken > 0 && broken <= (bytes.length / 200).ceil()) {
      return lenient;
    }
  }

  try {
    return const GbkCodec(allowInvalid: true).decode(bytes);
  } on FormatException {
    // Fall through to the most permissive UTF-8 decode.
  }

  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeUtf16(Uint8List bytes, Endian endian) {
  final safeLength = bytes.length - (bytes.length.isOdd ? 1 : 0);
  final data = ByteData.sublistView(bytes, 0, safeLength);
  final units = <int>[];
  for (var offset = 0; offset < safeLength; offset += 2) {
    units.add(data.getUint16(offset, endian));
  }
  var result = String.fromCharCodes(units);
  if (result.startsWith('\uFEFF')) {
    result = result.substring(1);
  }
  return result;
}
