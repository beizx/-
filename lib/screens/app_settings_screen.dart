import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/navigation/app_page_route.dart';
import '../core/theme/app_theme.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/common_widgets.dart';
import 'api_settings_screen.dart';
import 'reader_settings_screen.dart';

/// The second tab is deliberately a general settings page: translation is one
/// optional service here, not the identity of the app.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  Future<void> _openReaderSettings(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => const ReaderSettingsScreen()));
  }

  Future<void> _openTranslationSettings(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(AppPageRoute<void>(builder: (_) => const ApiSettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();
    final reader = settings.readerPreferences;
    final readingSeconds = library.readingProgress.values.fold<int>(
      0,
      (total, progress) => total + progress.readingSeconds,
    );
    final translated = library.translatedLanguageCount;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.accentWash,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(fontSize: 23),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '阅读是主角，翻译是随叫随到的工具',
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 0.3,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionLabel(title: '阅读'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.auto_stories_rounded,
                  iconColor: AppColors.accent,
                  title: '阅读偏好',
                  subtitle:
                      '字号 ${reader.fontSize.round()} · '
                      '${reader.mode.label} · ${reader.skin.label} '
                      '· ${reader.serif ? '衬线体' : '无衬线'}',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: AppColors.muted,
                  ),
                  onTap: () => _openReaderSettings(context),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.insights_rounded,
                            size: 18,
                            color: AppColors.jade,
                          ),
                          SizedBox(width: 9),
                          Text(
                            '阅读记录',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          MetricTile(
                            value: '${library.bookCount}',
                            label: '本藏书',
                            icon: Icons.menu_book_outlined,
                          ),
                          MetricTile(
                            value: '${library.readingProgress.length}',
                            label: '本开读过',
                            icon: Icons.bookmark_border_rounded,
                          ),
                          MetricTile(
                            value: _compactReadingTime(readingSeconds),
                            label: '累计阅读',
                            icon: Icons.schedule_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionLabel(
              title: '翻译',
              trailing: Text(
                translated == 0 ? '可选功能' : '已译 $translated 种语言',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.translate_rounded,
                  iconColor: AppColors.jade,
                  title: '翻译接口',
                  subtitle: settings.isCurrentProviderConfigured
                      ? '${settings.provider.name} · 密钥已保存在系统安全存储'
                      : '未配置也能读书；需要整书翻译时再来配置有道智云密钥',
                  trailing: StatusPill(
                    label: settings.isCurrentProviderConfigured ? '已就绪' : '未配置',
                    icon: settings.isCurrentProviderConfigured
                        ? Icons.check_circle_rounded
                        : Icons.key_off_outlined,
                    tone: settings.isCurrentProviderConfigured
                        ? StatusTone.success
                        : StatusTone.warning,
                  ),
                  onTap: () => _openTranslationSettings(context),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '翻译会把当前目标语言（${settings.targetLanguage.label}）整书保存到本机，'
                          '不配置接口也不影响导入、阅读、书签和阅读进度。',
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.55,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionLabel(title: '关于'),
            const SizedBox(height: 10),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.local_library_rounded,
                  iconColor: AppColors.accent,
                  title: AppInfo.name,
                  subtitle: '${AppInfo.versionLabel} · Flutter · 本地优先的小说阅读器',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: AppColors.muted,
                  ),
                  onTap: () => _showAbout(context),
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 13, 16, 15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '书籍、译文、阅读进度和书签都保存在设备本地。'
                          '只有你主动发起翻译时，才会把分段正文发送给你配置的翻译服务。',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.55,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Center(
              child: Text(
                '${AppInfo.name} · ${AppInfo.versionLabel}',
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1,
                  color: AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppInfo.name),
        content: const Text(
          '一个本地优先的小说阅读器：导入 TXT / EPUB，离线阅读，记录进度与书签。\n\n'
          '整书翻译是可选的附加功能，需要你自己的有道智云密钥。\n\n'
          '版本 ${AppInfo.versionLabel}（构建 ${AppInfo.buildNumber}）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: children),
    );
  }
}

/// Short form so three metric tiles fit on a narrow phone.
String _compactReadingTime(int seconds) {
  if (seconds < 60) return '0 分';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 时' : '$hours 时 $rest 分';
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.iconColor = AppColors.inkSoft,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.paperDeep,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}
