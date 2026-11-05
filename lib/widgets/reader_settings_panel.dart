import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/reader_settings.dart';

/// Shared reader preference editor used by the in-reader bottom sheet and the
/// standalone settings screen. All controls write through [onChanged], so the
/// reader can apply changes live.
class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.preferences,
    required this.onChanged,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;

  void _update(ReaderPreferences next) => onChanged(next.normalized());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '外观'),
              Tab(text: '排版'),
              Tab(text: '操作'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AppearanceTab(preferences: preferences, onUpdate: _update),
                _TypographyTab(preferences: preferences, onUpdate: _update),
                _ControlsTab(preferences: preferences, onUpdate: _update),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab({required this.preferences, required this.onUpdate});

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onUpdate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const _GroupLabel('阅读模式'),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.swap_vert_rounded,
                title: ReaderMode.scroll.label,
                description: '上下滚动正文，左右滑动换章',
                selected: preferences.mode == ReaderMode.scroll,
                onTap: () =>
                    onUpdate(preferences.copyWith(mode: ReaderMode.scroll)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                icon: Icons.menu_book_rounded,
                title: ReaderMode.page.label,
                description: '自动分页，左右翻页更像纸质书',
                selected: preferences.mode == ReaderMode.page,
                onTap: () =>
                    onUpdate(preferences.copyWith(mode: ReaderMode.page)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _GroupLabel('背景'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final skin in ReaderSkin.values) ...[
              Expanded(
                child: _SkinSwatch(
                  skin: skin,
                  selected: preferences.skin == skin,
                  onTap: () => onUpdate(preferences.copyWith(skin: skin)),
                ),
              ),
              if (skin != ReaderSkin.values.last) const SizedBox(width: 9),
            ],
          ],
        ),
        const SizedBox(height: 22),
        const _GroupLabel('字体'),
        const SizedBox(height: 9),
        for (var row = 0; row < ReaderTypeface.values.length; row += 2) ...[
          Row(
            children: [
              for (var column = 0; column < 2; column++) ...[
                if (column > 0) const SizedBox(width: 9),
                Expanded(
                  child: _TypefaceCard(
                    face: ReaderTypeface.values[row + column],
                    selected:
                        preferences.typeface ==
                        ReaderTypeface.values[row + column],
                    onTap: () => onUpdate(
                      preferences.copyWith(
                        typeface: ReaderTypeface.values[row + column],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (row + 2 < ReaderTypeface.values.length) const SizedBox(height: 9),
        ],
        const SizedBox(height: 8),
        const _Footnote('使用系统自带字体。自定义字体文件暂不支持，避免阅读中途找不到字。'),
        const SizedBox(height: 9),
        SegmentedButton<ReaderFontWeight>(
          segments: [
            for (final weight in ReaderFontWeight.values)
              ButtonSegment(value: weight, label: Text(weight.label)),
          ],
          selected: {preferences.fontWeight},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              onUpdate(preferences.copyWith(fontWeight: selection.first)),
        ),
        const SizedBox(height: 22),
        const _GroupLabel('阅读辅助'),
        const SizedBox(height: 4),
        _SwitchRow(
          icon: Icons.lightbulb_outline_rounded,
          title: '保持屏幕常亮',
          subtitle: '阅读时不自动熄屏，会稍微增加耗电',
          value: preferences.keepScreenOn,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(keepScreenOn: value)),
        ),
        _SwitchRow(
          icon: Icons.fullscreen_rounded,
          title: '隐藏状态栏',
          subtitle: '沉浸阅读时隐藏系统状态栏',
          value: preferences.hideStatusBar,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(hideStatusBar: value)),
        ),
        _SwitchRow(
          icon: Icons.schedule_rounded,
          title: '显示时间',
          subtitle: '在阅读区底部显示当前时间',
          value: preferences.showClock,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(showClock: value)),
        ),
        _SwitchRow(
          icon: Icons.notes_rounded,
          title: '显示章节名',
          subtitle: '在阅读区底部显示当前章节',
          value: preferences.showChapterTitle,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(showChapterTitle: value)),
        ),
        _SwitchRow(
          icon: Icons.percent_rounded,
          title: '显示阅读进度',
          subtitle: '在阅读区底部显示全书百分比',
          value: preferences.showProgress,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(showProgress: value)),
        ),
        _SwitchRow(
          icon: Icons.looks_one_outlined,
          title: '显示页码',
          subtitle: '翻页阅读时显示当前章节页码',
          value: preferences.showPageNumber,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(showPageNumber: value)),
        ),
        const SizedBox(height: 12),
        const _Footnote('阅读偏好会保存在本机，下次打开自动恢复。'),
      ],
    );
  }
}

class _TypographyTab extends StatelessWidget {
  const _TypographyTab({required this.preferences, required this.onUpdate});

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onUpdate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _SliderRow(
          title: '字号',
          valueLabel: preferences.fontSize.toStringAsFixed(0),
          value: preferences.fontSize,
          min: ReaderPreferences.minFontSize,
          max: ReaderPreferences.maxFontSize,
          divisions: 28,
          onChanged: (value) => onUpdate(preferences.copyWith(fontSize: value)),
          leading: _StepButton(
            icon: Icons.text_decrease_rounded,
            onTap: () => onUpdate(
              preferences.copyWith(fontSize: preferences.fontSize - 1),
            ),
          ),
          trailing: _StepButton(
            icon: Icons.text_increase_rounded,
            onTap: () => onUpdate(
              preferences.copyWith(fontSize: preferences.fontSize + 1),
            ),
          ),
        ),
        _SliderRow(
          title: '行距',
          valueLabel: preferences.lineHeight.toStringAsFixed(2),
          value: preferences.lineHeight,
          min: ReaderPreferences.minLineHeight,
          max: ReaderPreferences.maxLineHeight,
          divisions: 28,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(lineHeight: value)),
        ),
        _SliderRow(
          title: '段间距',
          valueLabel: '${preferences.paragraphSpacing.round()}',
          value: preferences.paragraphSpacing,
          min: ReaderPreferences.minParagraphSpacing,
          max: ReaderPreferences.maxParagraphSpacing,
          divisions: 28,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(paragraphSpacing: value)),
        ),
        _SliderRow(
          title: '首行缩进',
          valueLabel: '${preferences.firstLineIndent.toStringAsFixed(1)} 字',
          value: preferences.firstLineIndent,
          min: ReaderPreferences.minFirstLineIndent,
          max: ReaderPreferences.maxFirstLineIndent,
          divisions: 4,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(firstLineIndent: value)),
        ),
        const Divider(height: 32),
        _SliderRow(
          title: '左右边距',
          valueLabel: '${preferences.horizontalMargin.round()}',
          value: preferences.horizontalMargin,
          min: ReaderPreferences.minHorizontalMargin,
          max: ReaderPreferences.maxHorizontalMargin,
          divisions: 36,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(horizontalMargin: value)),
        ),
        _SliderRow(
          title: '上边距',
          valueLabel: '${preferences.topMargin.round()}',
          value: preferences.topMargin,
          min: ReaderPreferences.minVerticalMargin,
          max: ReaderPreferences.maxVerticalMargin,
          divisions: 28,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(topMargin: value)),
        ),
        _SliderRow(
          title: '下边距',
          valueLabel: '${preferences.bottomMargin.round()}',
          value: preferences.bottomMargin,
          min: ReaderPreferences.minVerticalMargin,
          max: ReaderPreferences.maxVerticalMargin,
          divisions: 28,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(bottomMargin: value)),
        ),
        const SizedBox(height: 6),
        const _Footnote('翻页模式会按当前屏幕、字号和边距重新分页；修改字号后页码会重新计算。'),
      ],
    );
  }
}

class _ControlsTab extends StatelessWidget {
  const _ControlsTab({required this.preferences, required this.onUpdate});

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onUpdate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _SwitchRow(
          icon: Icons.touch_app_outlined,
          title: '点击翻页',
          subtitle: '翻页模式下，点左侧上一页、点右侧下一页，点中间呼出工具栏',
          value: preferences.tapToTurnPage,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(tapToTurnPage: value)),
        ),
        _SwitchRow(
          icon: Icons.volume_up_outlined,
          title: '音量键翻页',
          subtitle:
              '阅读页获得焦点时，音量上翻到上一页，音量下翻到下一页；滚动模式则翻一屏。关闭后音量键仍调节系统音量。iOS 侧边音量键由系统接管。',
          value: preferences.volumeKeysTurnPages,
          onChanged: (value) =>
              onUpdate(preferences.copyWith(volumeKeysTurnPages: value)),
        ),
        const SizedBox(height: 14),
        const _GroupLabel('翻页动画'),
        const SizedBox(height: 9),
        SegmentedButton<ReaderTurnAnimation>(
          segments: [
            for (final animation in ReaderTurnAnimation.values)
              ButtonSegment(value: animation, label: Text(animation.label)),
          ],
          selected: {preferences.turnAnimation},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              onUpdate(preferences.copyWith(turnAnimation: selection.first)),
        ),
        const SizedBox(height: 22),
        _SwitchRow(
          icon: Icons.format_align_justify_rounded,
          title: '正文两端对齐',
          subtitle: '关闭后使用左对齐，更适合英文小说',
          value: preferences.justify,
          onChanged: (value) => onUpdate(preferences.copyWith(justify: value)),
        ),
        const SizedBox(height: 20),
        _GuideCard(
          icon: Icons.swipe_rounded,
          title: '翻页模式手势',
          lines: const [
            '左右滑动：翻页，翻到章节末自动进入下一章',
            '点击左 / 右：上一页 / 下一页',
            '点击中间：显示或隐藏工具栏',
            '音量键翻页开启后：音量上上一页，音量下下一页',
          ],
        ),
        const SizedBox(height: 12),
        _GuideCard(
          icon: Icons.vertical_align_center_rounded,
          title: '滚动模式手势',
          lines: const ['上下滚动：连续阅读本章', '左右滑动：切换上一章 / 下一章', '点击正文：显示或隐藏工具栏'],
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => onUpdate(const ReaderPreferences()),
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('恢复默认阅读设置'),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.inkSoft,
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: AppColors.muted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              height: 1.55,
              color: AppColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentWash : AppColors.paperDeep,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? AppColors.accent : AppColors.inkSoft,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.accent : AppColors.ink,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final ReaderSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 54,
            decoration: BoxDecoration(
              color: skin.background,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '字',
                style: TextStyle(
                  fontFamily: AppTheme.serif,
                  fontFamilyFallback: AppTheme.serifFallback,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: skin.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            skin.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.accent : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypefaceCard extends StatelessWidget {
  const _TypefaceCard({
    required this.face,
    required this.selected,
    required this.onTap,
  });

  final ReaderTypeface face;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentWash : AppColors.paperDeep,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Column(
          children: [
            Text(
              face.preview,
              style: TextStyle(
                fontFamily: face.fontFamily,
                fontFamilyFallback: face.fallback,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.accent : AppColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              face.label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.inkSoft),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.leading,
    this.trailing,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                valueLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 4)],
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: AppColors.accent,
                  inactiveColor: AppColors.line,
                  onChanged: onChanged,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, size: 17, color: AppColors.ink),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.jade),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '· ',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
