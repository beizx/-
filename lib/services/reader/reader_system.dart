import 'package:flutter/services.dart';

/// Small bridge for reader-only platform behaviour.
///
/// The channel is optional: widget tests and platforms without a handler fall
/// back to a no-op instead of breaking the reader.
abstract final class ReaderSystem {
  static const _channel = MethodChannel('com.yiyue.translation_app/reader');

  static Future<void> keepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', enabled);
    } on MissingPluginException {
      // Widget tests and unsupported platforms.
    } on PlatformException {
      // Never block reading because of a platform toggle.
    }
  }
}
