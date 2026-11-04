import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/theme/app_theme.dart';
import '../models/translation_provider.dart';
import '../state/settings_controller.dart';
import '../widgets/common_widgets.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  late final TextEditingController _appKeyController;
  late final TextEditingController _appSecretController;
  bool _obscureSecret = true;
  bool _saving = false;
  bool _testing = false;
  ApiConnectionTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _appKeyController = TextEditingController(
      text: settings.youdaoAppKey ?? '',
    );
    _appSecretController = TextEditingController(
      text: settings.youdaoAppSecret ?? '',
    );
  }

  @override
  void dispose() {
    _appKeyController.dispose();
    _appSecretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_appKeyController.text.trim().isEmpty ||
        _appSecretController.text.trim().isEmpty) {
      _showMessage('请先填写 App ID 与 App Secret');
      return;
    }

    setState(() => _saving = true);
    try {
      await context.read<SettingsController>().saveYoudaoCredentials(
        appKey: _appKeyController.text,
        appSecret: _appSecretController.text,
      );
      if (!mounted) return;
      setState(() => _testResult = null);
      _showMessage('配置已安全保存');
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    if (_appKeyController.text.trim().isEmpty ||
        _appSecretController.text.trim().isEmpty) {
      setState(() {
        _testResult = const ApiConnectionTestResult(
          success: false,
          message: '请先填写 App ID 与 App Secret',
        );
      });
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await context
        .read<SettingsController>()
        .testYoudaoConnection(
          appKey: _appKeyController.text,
          appSecret: _appSecretController.text,
        );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除接口密钥？'),
        content: const Text('App ID 与 App Secret 将从系统安全存储中删除。书库和已完成的译文不会受到影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await context.read<SettingsController>().clearYoudaoCredentials();
    if (!mounted) return;
    _appKeyController.clear();
    _appSecretController.clear();
    setState(() => _testResult = null);
    _showMessage('接口密钥已清除');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final canPop = Navigator.of(context).canPop();
    final configured = settings.isYoudaoConfigured;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        title: const Text('接口设置'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const Text(
              'TRANSLATION ENGINE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Text('让文字穿墙而过', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 7),
            const Text(
              '翻译能力由你选择的接口提供。使用自己的免费 API 密钥，按量消耗，不经过第三方中转服务器。',
              style: TextStyle(
                fontSize: 13,
                height: 1.65,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            _buildCurrentEngineCard(context, settings, configured),
            const SizedBox(height: 22),
            _buildCredentialCard(context, configured),
            const SizedBox(height: 22),
            _buildHowToCard(),
            const SizedBox(height: 22),
            _buildPlannedProviders(context),
            const SizedBox(height: 20),
            const InfoNote(
              text:
                  '密钥仅写入 Android Keystore / iOS Keychain。翻译时只把分段正文发送给你配置的翻译服务，整本书不会上传到任何自建服务器。',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '${AppInfo.name} ${AppInfo.versionLabel} · 接口适配层 v1',
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentEngineCard(
    BuildContext context,
    SettingsController settings,
    bool configured,
  ) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B244F), Color(0xFF372C5B)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentStrong,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.translate_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前引擎', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      settings.provider.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: configured ? '已配置' : '待配置',
                icon: configured
                    ? Icons.check_circle_rounded
                    : Icons.key_off_outlined,
                tone: configured ? StatusTone.success : StatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  size: 16,
                  color: AppColors.jade,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '默认路径  ${settings.sourceLanguage.label} → ${settings.targetLanguage.label}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                Text(
                  settings.provider.available ? '可用' : '未开放',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.jade,
                  ),
                ),
              ],
            ),
          ),
          if (settings.storageError != null) ...[
            const SizedBox(height: 12),
            InfoNote(
              text: settings.storageError!,
              icon: Icons.warning_amber_rounded,
              color: AppColors.danger,
              background: AppColors.dangerWash,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCredentialCard(BuildContext context, bool configured) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(title: '有道智云密钥'),
          const SizedBox(height: 7),
          Text(
            '在 ai.youdao.com 创建应用并开通「文本翻译」后，复制应用 ID 与应用密钥。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('App ID / 应用 ID'),
          const SizedBox(height: 7),
          TextField(
            controller: _appKeyController,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: '例如 3f8a2c...',
              prefixIcon: Icon(Icons.badge_outlined, size: 19),
            ),
            onChanged: (_) => _clearTestResult(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('App Secret / 应用密钥'),
          const SizedBox(height: 7),
          TextField(
            controller: _appSecretController,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: _obscureSecret,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '仅保存在系统安全存储中',
              prefixIcon: const Icon(Icons.key_rounded, size: 19),
              suffixIcon: IconButton(
                tooltip: _obscureSecret ? '显示密钥' : '隐藏密钥',
                icon: Icon(
                  _obscureSecret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
                onPressed: () {
                  setState(() => _obscureSecret = !_obscureSecret);
                },
              ),
            ),
            onChanged: (_) => _clearTestResult(),
          ),
          const SizedBox(height: 15),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _testResult == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _TestResultCard(result: _testResult!),
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing || _saving ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt_outlined, size: 18),
                  label: Text(_testing ? '测试中…' : '测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || _testing ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_outline_rounded, size: 18),
                  label: Text(_saving ? '保存中…' : '保存配置'),
                ),
              ),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving || _testing ? null : _clearCredentials,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('清除已保存的密钥'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _clearTestResult() {
    if (_testResult != null) {
      setState(() => _testResult = null);
    }
  }

  Widget _buildHowToCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(title: '如何获取免费密钥'),
          const SizedBox(height: 14),
          const _StepRow(
            number: '01',
            title: '注册有道智云',
            detail: '使用手机号或邮箱注册，进入控制台。',
          ),
          const _StepRow(
            number: '02',
            title: '创建应用并开通文本翻译',
            detail: '应用类型选择「文本翻译」，在服务页开通 API。',
          ),
          const _StepRow(
            number: '03',
            title: '复制应用 ID 与应用密钥',
            detail: '粘贴到上方表单，先测试连接，再保存配置。',
            isLast: true,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const SelectableText(
              'https://ai.youdao.com/',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.jade,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannedProviders(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(title: '更多引擎 · 接口位已预留'),
        const SizedBox(height: 11),
        for (final provider in TranslationProviders.plannedProviders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Opacity(
              opacity: 0.68,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.name,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            provider.description,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const StatusPill(label: '即将支持'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.inkSoft,
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.detail,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentWash,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
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
                  detail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.55,
                    color: AppColors.muted,
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

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({required this.result});

  final ApiConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final success = result.success;
    final color = success ? AppColors.jade : AppColors.danger;
    final background = success ? AppColors.jadeWash : AppColors.dangerWash;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (result.preview != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    '“Hello” → ${result.preview}',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: color),
                  ),
                ],
                if (result.latency != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '耗时 ${result.latencyLabel}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
