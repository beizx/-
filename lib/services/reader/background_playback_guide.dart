import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import 'reader_system.dart';

/// Whether the one-time background / battery guide should appear.
bool shouldShowBackgroundGuide({
  required bool dismissedForever,
  required bool introShown,
  required bool failureShown,
  required bool becauseFailed,
  required bool becauseInterrupted,
}) {
  if (dismissedForever) return false;
  if (becauseFailed || becauseInterrupted) return !failureShown;
  return !introShown;
}

/// Dismissible note shown the first time someone listens, and again if
/// playback fails or the last session was killed, until they opt out.
abstract final class BackgroundPlaybackGuide {
  static bool introShown = false;
  static bool failureShown = false;
  static bool _visible = false;

  static Future<void> maybeShow(
    BuildContext context, {
    required bool dismissedForever,
    required Future<void> Function() onDismissForever,
    bool becauseFailed = false,
    bool becauseInterrupted = false,
  }) async {
    if (_visible || !context.mounted) return;
    if (!shouldShowBackgroundGuide(
      dismissedForever: dismissedForever,
      introShown: introShown,
      failureShown: failureShown,
      becauseFailed: becauseFailed,
      becauseInterrupted: becauseInterrupted,
    )) {
      return;
    }

    _visible = true;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          _GuideDialog(becauseFailed: becauseFailed || becauseInterrupted),
    );
    _visible = false;
    if (becauseFailed || becauseInterrupted) {
      failureShown = true;
    } else {
      introShown = true;
    }
    if (action == 'dismiss') {
      await onDismissForever();
    } else if (action == 'settings') {
      final opened = await ReaderSystem.openBackgroundSettings();
      if (!opened && context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('请到系统设置中允许本应用在后台运行')));
      }
    }
  }
}

class _GuideDialog extends StatelessWidget {
  const _GuideDialog({required this.becauseFailed});

  final bool becauseFailed;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final android = platform == TargetPlatform.android;
    final ios = platform == TargetPlatform.iOS;
    final title = becauseFailed ? '听书可能被系统关掉了' : '让听书在后台继续';
    final body = android
        ? '锁屏或切到其他应用时，部分手机会用省电策略停掉朗读。可以在系统设置里允许「${AppInfo.name}」后台运行，并把电池优化设为不限制。这不是必须的，随时可以关掉这个提示。'
        : ios
        ? 'iOS 已为本应用申请后台音频。如果锁屏后听书停止，请打开系统「设置」中的「${AppInfo.name}」，确认后台 App 刷新没有被关掉。侧边音量键仍由系统控制。'
        : '如果锁屏后听书停止，请在系统设置里允许本应用后台运行。这不是必须的。';

    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('later'),
          child: const Text('稍后'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('dismiss'),
          child: const Text('不再提示'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('settings'),
          child: const Text('去系统设置'),
        ),
      ],
    );
  }
}
