import 'dart:io';

import 'package:flutter/services.dart';

/// A document another app handed to us ("用其他应用打开" in QQ, Files on iOS).
class IncomingFile {
  const IncomingFile({required this.path, required this.name});

  final String path;
  final String name;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// Bridge to the native document receivers.
///
/// Android delivers `ACTION_VIEW` / `ACTION_SEND` intents, iOS delivers
/// `application(_:open:)` URLs; both copy the file into the app sandbox first
/// and then hand us the path. A cold start is drained via [takePending], and
/// files arriving while the app is running are pushed through [bind].
class ExternalFileService {
  ExternalFileService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    // Installed immediately so a push that arrives before the UI subscribes is
    // queued rather than dropped.
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onFileOpened') return null;
      final file = _decode(call.arguments);
      if (file != null) await _deliver(file);
      return null;
    });
  }

  static const channelName = 'com.yiyue.translation_app/files';
  static const List<String> supportedExtensions = ['txt', 'epub'];

  final MethodChannel _channel;
  final List<IncomingFile> _queue = [];
  final Set<String> _seenPaths = {};
  Future<void> Function(IncomingFile file)? _handler;

  /// Registers for files that arrive while the app is running.
  void bind(Future<void> Function(IncomingFile file) handler) {
    _handler = handler;
  }

  /// Returns a file that launched the app, if any.
  Future<IncomingFile?> takePending() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('takePendingFile');
      final file = _decode(raw);
      if (file == null) return null;
      if (!_seenPaths.add(file.path)) return null;
      return file;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Drains anything queued before [bind] was called.
  Future<void> flushQueue() async {
    while (_queue.isNotEmpty) {
      final file = _queue.removeAt(0);
      await _handler?.call(file);
    }
  }

  Future<void> _deliver(IncomingFile file) async {
    if (!_seenPaths.add(file.path)) return;
    final handler = _handler;
    if (handler == null) {
      _queue.add(file);
      return;
    }
    await handler(file);
  }

  IncomingFile? _decode(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path']?.toString();
    final name = raw['name']?.toString();
    if (path == null || path.isEmpty) return null;
    return IncomingFile(
      path: path,
      name: (name == null || name.isEmpty) ? File(path).uri.pathSegments.last : name,
    );
  }

  /// Reads the sandboxed copy; bounded so a hostile file cannot exhaust memory.
  static Future<Uint8List> readBytes(IncomingFile file) async {
    final handle = File(file.path);
    return handle.readAsBytes();
  }
}
