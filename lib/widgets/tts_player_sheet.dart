import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/tts_settings.dart';
import '../state/settings_controller.dart';
import '../state/tts_controller.dart';
import 'book_cover.dart';

/// 听书 player, modelled on QQ 浏览器 / 微信读书 style bottom players:
/// a sheet you can raise from the reader, with speed chips, a sleep timer,
/// previous / next sentence and chapter jumps.
Future<void> showTtsPlayerSheet(BuildContext context, {Book? book}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TtsPlayerSheet(book: book),
  );
}

class TtsPlayerSheet extends StatelessWidget {
  const TtsPlayerSheet({super.key, this.book});

  final Book? book;

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsController>();
    final settings = context.watch<SettingsController?>();
    final activeBook = book ?? tts.book;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.line),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentStrong,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '听书',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  if (activeBook != null)
                    BookCover(
                      title: activeBook.meta.title,
                      format: activeBook.meta.format,
                      width: 30,
                      height: 40,
                      showFormatLabel: false,
                    ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tts.chapterTitle ?? activeBook?.meta.title ?? '还没有开始朗读',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              _NowPlayingCard(tts: tts),
              const SizedBox(height: 14),
              _ProgressBar(tts: tts),
              const SizedBox(height: 14),
              _TransportRow(tts: tts, settings: settings),
              const SizedBox(height: 16),
              _SpeedRow(tts: tts, settings: settings),
              const SizedBox(height: 10),
              _SleepAndAutoNext(tts: tts, settings: settings),
              if (tts.isActive) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '后台播放已开启：锁屏、通知栏与耳机按键都能控制朗读',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (tts.error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tts.error!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.tts});

  final TtsController tts;

  @override
  Widget build(BuildContext context) {
    final text = tts.activeText?.trim() ?? '';
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.format_quote_rounded,
            size: 17,
            color: AppColors.accentStrong,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text.isEmpty ? '点下面的按钮开始朗读这一章' : text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: text.isEmpty ? AppColors.muted : AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.tts});

  final TtsController tts;

  @override
  Widget build(BuildContext context) {
    final total = tts.segmentCount;
    final current = total == 0 ? 0 : tts.segmentIndex + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : tts.chapterProgress,
            minHeight: 3,
            backgroundColor: AppColors.line,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.accentStrong,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              total == 0 ? '第 — / — 句' : '第 $current / $total 句',
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
            const Spacer(),
            if (tts.sleepAtChapterEnd)
              const Text(
                '本章播完停止',
                style: TextStyle(fontSize: 10.5, color: AppColors.jade),
              )
            else if (tts.sleepMinutes > 0)
              Text(
                '${tts.sleepMinutes} 分钟后停止',
                style: const TextStyle(fontSize: 10.5, color: AppColors.jade),
              ),
          ],
        ),
      ],
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.tts, required this.settings});

  final TtsController tts;
  final SettingsController? settings;

  @override
  Widget build(BuildContext context) {
    final playing = tts.isPlaying;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          tooltip: '上一句',
          icon: Icons.skip_previous_rounded,
          onTap: tts.hasContent ? () => tts.skipSegment(-1) : null,
        ),
        _RoundButton(
          tooltip: '上一章',
          icon: Icons.keyboard_double_arrow_left_rounded,
          onTap: tts.hasContent ? () => tts.skipChapter(-1) : null,
        ),
        GestureDetector(
          onTap: () => _handlePrimary(context),
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentStrong,
            ),
            child: Icon(
              playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
        _RoundButton(
          tooltip: '下一章',
          icon: Icons.keyboard_double_arrow_right_rounded,
          onTap: tts.hasContent ? () => tts.skipChapter(1) : null,
        ),
        _RoundButton(
          tooltip: '下一句',
          icon: Icons.skip_next_rounded,
          onTap: tts.hasContent ? () => tts.skipSegment(1) : null,
        ),
      ],
    );
  }

  Future<void> _handlePrimary(BuildContext context) async {
    if (!tts.hasContent) {
      final book = tts.book;
      if (book != null) {
        unawaited(tts.startChapter(book, tts.chapterIndex));
      }
      return;
    }
    await tts.toggle();
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 24,
            color: onTap == null
                ? AppColors.muted.withValues(alpha: 0.5)
                : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({required this.tts, required this.settings});

  final TtsController tts;
  final SettingsController? settings;

  @override
  Widget build(BuildContext context) {
    final current = tts.preferences.rate;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TtsPreferences.speedChoices.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final rate = TtsPreferences.speedChoices[index];
          final selected = (rate - current).abs() < 0.001;
          return GestureDetector(
            onTap: () => _select(rate),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: selected ? AppColors.accentWash : AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? AppColors.accentStrong : AppColors.line,
                ),
              ),
              child: Text(
                TtsPreferences.labelForRate(rate),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.accentStrong : AppColors.muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _select(double rate) {
    final next = tts.preferences.copyWith(rate: rate);
    unawaited(tts.updatePreferences(next));
    final controller = settings;
    if (controller != null) {
      unawaited(controller.setTtsPreferences(next));
    }
  }
}

class _SleepAndAutoNext extends StatelessWidget {
  const _SleepAndAutoNext({required this.tts, required this.settings});

  final TtsController tts;
  final SettingsController? settings;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          label: _sleepLabel,
          icon: Icons.bedtime_outlined,
          active: tts.sleepMinutes > 0 || tts.sleepAtChapterEnd,
          onTap: () => _pickSleepTimer(context),
        ),
        _Chip(
          label: tts.preferences.autoNextChapter ? '自动下一章' : '读完本章停止',
          icon: Icons.auto_awesome_motion_outlined,
          active: tts.preferences.autoNextChapter,
          onTap: () {
            final next = tts.preferences.copyWith(
              autoNextChapter: !tts.preferences.autoNextChapter,
            );
            unawaited(tts.updatePreferences(next));
            final controller = settings;
            if (controller != null) {
              unawaited(controller.setTtsPreferences(next));
            }
          },
        ),
        _Chip(
          label: '音色',
          icon: Icons.record_voice_over_outlined,
          active: tts.preferences.voiceName != null,
          onTap: () => _pickVoice(context),
        ),
      ],
    );
  }

  Future<void> _pickVoice(BuildContext context) async {
    final voices = await tts.availableVoices();
    if (!context.mounted) return;
    if (voices.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('系统里没有可用的语音包，请先在系统设置里安装')),
      );
      return;
    }
    final current = tts.preferences.voiceName;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paperDeep,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.6,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '选择音色',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: voices.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        title: const Text('系统默认'),
                        trailing: _voiceTrailing(current == null),
                        onTap: () => Navigator.of(sheetContext).pop('__default__'),
                      );
                    }
                    final voice = voices[index - 1];
                    return ListTile(
                      title: Text(voice.label),
                      trailing: _voiceTrailing(current == voice.name),
                      onTap: () => Navigator.of(sheetContext).pop(voice.name),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    final next = choice == '__default__'
        ? tts.preferences.copyWith(clearVoice: true)
        : tts.preferences.copyWith(voiceName: choice);
    unawaited(tts.updatePreferences(next));
    final controller = settings;
    if (controller != null) {
      unawaited(controller.setTtsPreferences(next));
    }
  }

  Widget _voiceTrailing(bool selected) {
    return Icon(
      selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
      size: 18,
      color: selected ? AppColors.accentStrong : AppColors.muted,
    );
  }

  String get _sleepLabel {
    if (tts.sleepAtChapterEnd) return '本章播完停';
    if (tts.sleepMinutes > 0) return '${tts.sleepMinutes} 分钟';
    return '定时关闭';
  }

  Future<void> _pickSleepTimer(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paperDeep,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '定时关闭',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            for (final entry in const [
              ('off', '关闭定时'),
              ('chapter', '播完本章停止'),
              ('15', '15 分钟后'),
              ('30', '30 分钟后'),
              ('60', '60 分钟后'),
            ])
              ListTile(
                title: Text(entry.$2),
                trailing: Icon(
                  _isSelected(entry.$1)
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: _isSelected(entry.$1)
                      ? AppColors.accentStrong
                      : AppColors.muted,
                ),
                onTap: () => Navigator.of(sheetContext).pop(entry.$1),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case 'off':
        tts.setSleepTimer();
      case 'chapter':
        tts.setSleepTimer(atChapterEnd: true);
      default:
        tts.setSleepTimer(minutes: int.tryParse(choice) ?? 0);
    }
  }

  bool _isSelected(String key) {
    return switch (key) {
      'off' => tts.sleepMinutes == 0 && !tts.sleepAtChapterEnd,
      'chapter' => tts.sleepAtChapterEnd,
      _ => tts.sleepMinutes == int.tryParse(key),
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accentWash : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.accentStrong : AppColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppColors.accentStrong : AppColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.accentStrong : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
