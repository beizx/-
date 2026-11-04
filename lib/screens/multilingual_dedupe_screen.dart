import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/text_utils.dart';
import '../models/book.dart';
import '../models/language.dart';
import '../services/dedupe/multilingual_dedupe_service.dart';
import '../services/export_service.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/common_widgets.dart';
import 'book_detail_screen.dart';

/// Lets the user remove one side of adjacent, different-language paragraphs
/// that look like an original and its translation.
///
/// The original book is never mutated: applying the result creates a new book.
class MultilingualDedupeScreen extends StatefulWidget {
  const MultilingualDedupeScreen({super.key, required this.book});

  final Book book;

  @override
  State<MultilingualDedupeScreen> createState() =>
      _MultilingualDedupeScreenState();
}

class _MultilingualDedupeScreenState extends State<MultilingualDedupeScreen> {
  late AppLanguage _keepLanguage;
  DedupeAnalysis? _analysis;
  final Set<String> _selectedIds = {};
  bool _initialized = false;
  bool _analyzing = true;
  bool _generating = false;
  int _analysisGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferred = context.read<SettingsController>().targetLanguage;
    _keepLanguage =
        MultilingualDedupeService.supportedLanguageCodes.contains(
          preferred.code,
        )
        ? preferred
        : Languages.zh;
    Future<void>.microtask(_analyze);
  }

  Future<void> _analyze() async {
    final generation = ++_analysisGeneration;
    setState(() {
      _analyzing = true;
      _analysis = null;
      _selectedIds.clear();
    });

    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted || generation != _analysisGeneration) return;

    try {
      final analysis = MultilingualDedupeService.analyze(
        widget.book,
        keepLanguage: _keepLanguage,
      );
      if (!mounted || generation != _analysisGeneration) return;
      setState(() {
        _analysis = analysis;
        _selectedIds
          ..clear()
          ..addAll(analysis.candidates.map((candidate) => candidate.id));
        _analyzing = false;
      });
    } on DedupeException catch (error) {
      if (!mounted || generation != _analysisGeneration) return;
      setState(() => _analyzing = false);
      _showMessage(error.message);
    }
  }

  void _chooseLanguage(AppLanguage language) {
    if (_generating || language.code == _keepLanguage.code) return;
    setState(() => _keepLanguage = language);
    _analyze();
  }

  void _setAllSelected(bool selected) {
    final candidates = _analysis?.candidates ?? const <DedupeCandidate>[];
    setState(() {
      _selectedIds.clear();
      if (selected) {
        _selectedIds.addAll(candidates.map((candidate) => candidate.id));
      }
    });
  }

  Future<void> _openPreview(DedupeCandidate candidate) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    '疑似对照段落',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${candidate.chapterTitle} · 共 2 段',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _PreviewBlock(
                    label: '保留 · ${candidate.keepLanguage.label}',
                    text: candidate.keepText,
                    color: AppColors.jade,
                    background: AppColors.jadeWash,
                  ),
                  const SizedBox(height: 10),
                  _PreviewBlock(
                    label: '移除 · ${candidate.removeLanguage.label}',
                    text: candidate.removeText,
                    color: AppColors.danger,
                    background: AppColors.dangerWash,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _generate({bool exportAfter = false}) async {
    final analysis = _analysis;
    if (analysis == null || _generating || _selectedIds.isEmpty) return;
    final selected = analysis.candidates
        .where((candidate) => _selectedIds.contains(candidate.id))
        .toList(growable: false);
    if (selected.isEmpty) return;

    setState(() => _generating = true);
    try {
      final generated = MultilingualDedupeService.generateDedupedBook(
        source: widget.book,
        keepLanguage: _keepLanguage,
        selected: selected,
      );
      await context.read<LibraryController>().addBook(generated);
      if (!mounted) return;
      _showMessage('已生成「${generated.title}」');

      if (exportAfter) {
        await _exportBook(generated);
        if (!mounted) return;
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => BookDetailScreen(book: generated),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        final message = error is DedupeException ? error.message : '$error';
        _showMessage('生成去重版失败：$message');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<ExportFormat?> _pickExportFormat(Book book) {
    return showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出去重文件', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '「${book.title}」共 ${book.chapters.length} 章，'
                '文件写入应用沙盒后由系统分享面板保存或发送。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _ExportFormatTile(
                icon: Icons.text_snippet_outlined,
                title: 'TXT 纯文本',
                subtitle: '轻量、兼容性最好，适合继续编辑或再翻译',
                onTap: () => Navigator.of(context).pop(ExportFormat.txt),
              ),
              const SizedBox(height: 9),
              _ExportFormatTile(
                icon: Icons.menu_book_outlined,
                title: 'EPUB 电子书',
                subtitle: '保留章节结构，可直接导入阅读器',
                onTap: () => Navigator.of(context).pop(ExportFormat.epub),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportBook(Book book) async {
    final format = await _pickExportFormat(book);
    if (format == null || !mounted) return;
    try {
      final store = context.read<LibraryController>().store;
      await ExportService(store).shareBookExport(
        book: book,
        format: format,
        languageCode: _keepLanguage.code,
      );
      if (mounted) {
        _showMessage(
          '${format == ExportFormat.epub ? 'EPUB' : 'TXT'} 文件已生成，'
          '可在分享面板中保存',
        );
      }
    } on Object catch (error) {
      if (mounted) _showMessage('导出失败：$error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    final candidates = analysis?.candidates ?? const <DedupeCandidate>[];

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('多语去重')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: _buildHeader(context, analysis),
            ),
          ),
          if (_analyzing)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      SizedBox(height: 13),
                      Text(
                        '正在扫描相邻段落…',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (candidates.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: _DedupeEmptyState(
                  keepLanguage: _keepLanguage,
                  onChooseLanguage: _chooseLanguage,
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _buildSelectionBar(context, candidates.length),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              sliver: SliverList.builder(
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final candidate = candidates[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CandidateCard(
                      candidate: candidate,
                      groupNumber: index + 1,
                      selected: _selectedIds.contains(candidate.id),
                      onChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedIds.add(candidate.id);
                          } else {
                            _selectedIds.remove(candidate.id);
                          }
                        });
                      },
                      onPreview: () => _openPreview(candidate),
                    ),
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  Widget _buildHeader(BuildContext context, DedupeAnalysis? analysis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MULTILINGUAL CLEANUP',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        Text('同一段话，只留一边', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 7),
        const Text(
          '识别相邻的中文、日语、英语、韩语段落，保留你选择的语言版本。'
          '适合处理「原文一段 + 译文一段」交替出现的 TXT / EPUB。',
          style: TextStyle(fontSize: 13, height: 1.65, color: AppColors.muted),
        ),
        const SizedBox(height: 15),
        const InfoNote(
          text:
              '这是本地结构识别，不调用翻译接口：依据语言切换与段落长度比例判断疑似对照，'
              '不代表语义必然相同。请逐组预览并勾选；生成的是新书，原书不会被修改。',
          icon: Icons.rule_rounded,
          color: AppColors.gold,
          background: AppColors.goldWash,
        ),
        const SizedBox(height: 20),
        const SectionLabel(title: '保留哪种语言'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final language in MultilingualDedupeService.supportedLanguages)
              ChoiceChip(
                label: Text(language.label),
                selected: _keepLanguage.code == language.code,
                showCheckmark: false,
                onSelected: (_) => _chooseLanguage(language),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          '当前预览：保留${_keepLanguage.label}，移除相邻的其他语言段落',
          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
        if (analysis != null) ...[
          const SizedBox(height: 18),
          _AnalysisStats(analysis: analysis),
        ],
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context, int count) {
    final allSelected = _selectedIds.length == count;
    return Row(
      children: [
        Expanded(
          child: Text(
            '疑似对照 $count 组',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: _generating ? null : () => _setAllSelected(!allSelected),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final selectedCount = _selectedIds.length;
    final canGenerate =
        !_analyzing && !_generating && _analysis != null && selectedCount > 0;

    return Container(
      height: 112 + bottomInset,
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '保留${_keepLanguage.label}版 · 原书不变',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              Text(
                selectedCount == 0 ? '尚未勾选' : '将移除 $selectedCount 段',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canGenerate ? () => _generate() : null,
                  icon: const Icon(Icons.library_add_outlined, size: 17),
                  label: const Text('仅加入书库'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canGenerate
                      ? () => _generate(exportAfter: true)
                      : null,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(_generating ? '正在生成…' : '生成并导出'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisStats extends StatelessWidget {
  const _AnalysisStats({required this.analysis});

  final DedupeAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _StatCell(value: '${analysis.candidates.length}', label: '组疑似对照'),
          const _StatDivider(),
          _StatCell(value: '${analysis.affectedChapterCount}', label: '个章节'),
          const _StatDivider(),
          _StatCell(
            value: formatCharacterCount(analysis.removableCharacterCount),
            label: '可移除字数',
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTheme.serif,
              fontFamilyFallback: AppTheme.serifFallback,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: AppColors.line);
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.groupNumber,
    required this.selected,
    required this.onChanged,
    required this.onPreview,
  });

  final DedupeCandidate candidate;
  final int groupNumber;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: selected ? AppColors.jade : AppColors.line,
          width: selected ? 1.3 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            onTap: () => onChanged(!selected),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 12, 6),
              child: Row(
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (value) => onChanged(value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${candidate.chapterTitle} · 组 $groupNumber',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: selected ? '将移除' : '跳过',
                    tone: selected ? StatusTone.warning : StatusTone.neutral,
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CandidateTextBlock(
                  label: '保留 · ${candidate.keepLanguage.label}',
                  text: candidate.keepText,
                  color: AppColors.jade,
                  background: AppColors.jadeWash.withValues(alpha: 0.55),
                ),
                const SizedBox(height: 8),
                _CandidateTextBlock(
                  label: '移除 · ${candidate.removeLanguage.label}',
                  text: candidate.removeText,
                  color: AppColors.danger,
                  background: AppColors.dangerWash.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: TextButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.open_in_full_rounded, size: 14),
                label: const Text('查看全文'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateTextBlock extends StatelessWidget {
  const _CandidateTextBlock({
    required this.label,
    required this.text,
    required this.color,
    required this.background,
  });

  final String label;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
    required this.label,
    required this.text,
    required this.color,
    required this.background,
  });

  final String label;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.75,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportFormatTile extends StatelessWidget {
  const _ExportFormatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accentWash,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: AppColors.accent),
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DedupeEmptyState extends StatelessWidget {
  const _DedupeEmptyState({
    required this.keepLanguage,
    required this.onChooseLanguage,
  });

  final AppLanguage keepLanguage;
  final ValueChanged<AppLanguage> onChooseLanguage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.jadeWash,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: AppColors.jade,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text('没有找到疑似对照段落', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            '当前书籍中没有与「${keepLanguage.label}」段落相邻的其他语言段落。'
            '可以换一种保留语言，或确认文件本身是否双语对照排版。',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.65,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            alignment: WrapAlignment.center,
            children: [
              for (final language
                  in MultilingualDedupeService.supportedLanguages)
                if (language.code != keepLanguage.code)
                  ActionChip(
                    label: Text('保留${language.label}'),
                    onPressed: () => onChooseLanguage(language),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${AppInfo.name} ${AppInfo.versionLabel} · 本地分析',
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
