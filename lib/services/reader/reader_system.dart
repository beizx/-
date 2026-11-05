import 'package:flutter/services.dart';

/// Small bridge for reader-only platform behaviour.
///
/// The channel is optional: widget tests and platforms without a handler fall
/// back to a no-op instead of breaking the reader.
abstract final class ReaderSystem {
  static const _channel = MethodChannel('com.yiyue.translation_app/reader');
  static const _volumeChannel = MethodChannel(
    'com.yiyue.translation_app/volume',
  );

  static Future<void> keepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', enabled);
    } on MissingPluginException {
      // Widget tests and unsupported platforms.
    } on PlatformException {
      // Never block reading because of a platform toggle.
    }
  }

  /// Asks Android to deliver volume keys to the reader instead of the mixer.
  ///
  /// Other platforms ignore the call. The reader only enables this while it
  /// is the current route and the preference is on.
  static Future<void> setVolumeKeyCapture(bool enabled) async {
    try {
      await _volumeChannel.invokeMethod<void>('setCapture', enabled);
    } on MissingPluginException {
      // Desktop, iOS and widget tests have no capture hook.
    } on PlatformException {
      // Leave the hardware keys with the system.
    }
  }

  /// Receives volume-key directions from Android (`-1` up/previous, `1` down).
  static void bindVolumeKeys(void Function(int direction)? onKey) {
    if (onKey == null) {
      _volumeChannel.setMethodCallHandler(null);
      return;
    }
    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method != 'onVolumeKey') return;
      final argument = call.arguments;
      final direction = argument is int
          ? argument
          : argument is num
          ? argument.toInt()
          : 0;
      if (direction != 0) onKey(direction);
    });
  }

  /// Opens the system screen where the user can allow background playback.
  ///
  /// Android prefers the battery-optimization list. iOS opens this app's
  /// settings page. Returns false when the platform cannot show either.
  static Future<bool> openBackgroundSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openBackgroundSettings',
      );
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
