import 'dart:math';

/// Short, collision-resistant identifiers for locally created records.
String generateId([String prefix = '']) {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = Random.secure().nextInt(0xFFFFFF).toRadixString(36);
  return '$prefix${now}_$random';
}
