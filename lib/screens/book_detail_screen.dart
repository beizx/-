import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/text_utils.dart';
import '../models/book.dart';
import '../models/language.dart';
import '../models/reading_progress.dart';
import '../services/export_service.dart';
import '../services/translation/translation_engine.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../state/translation_controller.dart';
import '../widgets/book_cover.dart';
import '../widgets/common_widgets.dart';
import '../widgets/language_picker_sheet.dart';
import 'api_settings_screen.dart';
import 'chapter_reader_screen.dart';
import 'multilingual_dedupe_screen.dart';

class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({super.key, required this.book});

  final Book book;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late AppLanguage _sourceLanguage;
  late AppLanguage _targetLanguage;
  late TranslationController _translationController;
  TranslationRecord? _record;
  bool _initialized = false;
  bool _recordLoading = true;
  bool _starting = false;
  bool _exporting = false;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = context.read<SettingsController>();
    _translationController = context.read<TranslationController>();
    _sourceLanguage = settings.sourceLanguage;
    _targetLanguage = settings.targetLanguage;
    Future<void>.microtask(_loadRecord);
  }

  @override
  void dispose() {
    _translationController.cancelIfRunningFor(widget.book.id);
    super.dispose();
  }

  Future<void> _loadRecord() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _recordLoading = true;
        _record = null;
      });
    }
    final record = await _translationController.loadTranslation(
      widget.book.id,
      _targetLanguage.code,
    );
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _record = record;
      _recordLoading = false;
    });
  }

  Future<void> _pickSourceLanguage() async {
    if (_isThisBookTranslating) return;
    final result = await showLanguagePicker(
      context: context,
      title: '原文语言',
      subtitle: '不确定时交给「自动识别」',
      languages: Languages.sourceOptions,
      selected: _sourceLanguage,
    );
    if (result == null || !mounted) return;
    setState(() => _sourceLanguage = result);
    await context.read<SettingsController>().setLanguages(source: result);
  }

  Future<void> _pickTargetLanguage() async {
    if (_isThisBookTranslating) return;
    final result = await showLanguagePicker(
      context: context,
      title: '目标语言',
      subtitle: '翻译结果会按语言保存在本机',
      languages: Languages.targetOptions,
      selected: _targetLanguage,
    );
    if (result == null || !mounted) return;
    setState(() => _targetLanguage = result);
    await context.read<SettingsController>().setLanguages(
      target: _targetLanguage,
    );
    if (!mounted) return;
    await _loadRecord();
  }

  bool get _isThisBookTranslating {
    final job = _translationController.activeJob;
    return job != null &&
        job.isRunning &&
        job.bookId == widget.book.id &&
        job.targetLanguage.code == _targetLanguage.code;
  }

  Future<bool> _ensureApiConfigured() async {
    final settings = context.read<SettingsController>();
    if (settings.isCurrentProviderConfigured) return true;

    final goConfigure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('还差一把接口钥匙'),
        content: const Text(
          '翻译整本书需要一个翻译接口。请在「接口设置」中填入你自己的有道智云 App ID 与 App Secret。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去配置'),
          ),
        ],
      ),
    );
    if (goConfigure == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ApiSettingsScreen()),
      );
    }
    if (!mounted) return false;
    return context.read<SettingsController>().isCurrentProviderConfigured;
  }

  Future<void> _startTranslation() async {
    if (_starting || _recordLoading || _isThisBookTranslating) return;
    final translation = context.read<TranslationController>();
    if (translation.activeJob?.isRunning ?? false) {
      _showMessage('另一本书正在翻译，请先等待或取消');
      return;
    }
    if (!await _ensureApiConfigured()) return;
    if (!mounted) return;

    if (_record != null) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新翻译这一版？'),
          content: Text(
            '《${widget.book.title}》已有${_targetLanguage.label}译文。重新翻译会覆盖当前目标语言的旧译文。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('重新翻译'),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }
    if (!mounted) return;

    final settings = context.read<SettingsController>();
    final engine = settings.createEngine();
    if (engine == null) {
      await _ensureApiConfigured();
      return;
    }

    setState(() => _starting = true);
    try {
      final record = await translation.startTranslation(
        book: widget.book,
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
        engine: engine,
      );
      if (!mounted) return;
      final job = translation.activeJob;
      if (record != null) {
        setState(() => _record = record);
        _showMessage('《${widget.book.title}》翻译完成');
        translation.clearFinishedJob();
        await context.read<LibraryController>().refreshTranslatedLanguages();
      } else if (job?.status == TranslationJobStatus.cancelled) {
        _showMessage('翻译已取消，原书与已有译文不受影响');
        translation.clearFinishedJob();
      } else {
        _showMessage(job?.error ?? '翻译失败，请稍后重试');
        translation.clearFinishedJob();
      }
    } on TranslationException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object catch (error) {
      if (mounted) _showMessage('翻译失败：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _exportTranslation() async {
    final record = _record;
    if (record == null || _exporting) return;
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出译文', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '将调用系统分享面板，保存到「文件」或发送给其他应用。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _ExportOptionTile(
                icon: Icons.text_snippet_outlined,
                title: 'TXT 纯文本',
                subtitle: '轻量、兼容性最好，适合继续编辑',
                onTap: () => Navigator.of(context).pop(ExportFormat.txt),
              ),
              const SizedBox(height: 9),
              _ExportOptionTile(
                icon: Icons.menu_book_outlined,
                title: 'EPUB 电子书',
                subtitle: '保留章节结构，适合阅读器',
                onTap: () => Navigator.of(context).pop(ExportFormat.epub),
              ),
            ],
          ),
        ),
      ),
    );
    if (format == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final store = context.read<LibraryController>().store;
      await ExportService(
        store,
      ).shareExport(book: widget.book, record: record, format: format);
      if (mounted) {
        _showMessage(
          '${format == ExportFormat.epub ? 'EPUB' : 'TXT'} 文件已生成，可在分享面板中保存',
        );
      }
    } on Object catch (error) {
      if (mounted) _showMessage('导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteBook() async {
    if (_isThisBookTranslating || _starting) {
      _showMessage('翻译进行中，请先取消翻译再删除书籍');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这本书？'),
        content: Text('《${widget.book.title}》的本地原书与所有语言的译文都会被删除，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<LibraryController>().deleteBook(widget.book.id);
      if (!mounted) return;
      context.read<TranslationController>().evictBook(widget.book.id);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) _showMessage('删除失败：$error');
    }
  }

  void _openChapter(int index) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => ChapterReaderScreen(
          book: widget.book,
          initialChapterIndex: index,
          translation: _record,
        ),
      ),
    );
  }

  Future<void> _showAllChapters() async {
    final library = context.read<LibraryController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (sheetContext) {
        final progress = library.progressFor(widget.book.id);
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.list_rounded,
                        size: 19,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '全部章节',
                        style: TextStyle(
                          fontFamily: AppTheme.serif,
                          fontFamilyFallback: AppTheme.serifFallback,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '共 ${widget.book.chapters.length} 章',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.book.chapters.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final chapter = widget.book.chapters[index];
                      final current = progress?.chapterIndex == index;
                      return Container(
                        color: current
                            ? AppColors.accentWash.withValues(alpha: 0.5)
                            : Colors.transparent,
                        child: _ChapterRow(
                          chapter: chapter,
                          translated: _record?.chapterFor(chapter.id) != null,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _openChapter(index);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDedupe() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultilingualDedupeScreen(book: widget.book),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();
    final translation = context.watch<TranslationController>();
    final progress = library.progressFor(widget.book.id);
    final bookmarkCount = library.bookmarksFor(widget.book.id).length;
    final job = translation.activeJob;
    final thisJob =
        job != null &&
            job.isRunning &&
            job.bookId == widget.book.id &&
            job.targetLanguage.code == _targetLanguage.code
        ? job
        : null;
    final anotherJobRunning =
        (job?.isRunning ?? false) && job!.bookId != widget.book.id;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('书籍详情'),
        actions: [
          IconButton(
            tooltip: '多语去重',
            onPressed: _openDedupe,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'delete') _deleteBook();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    SizedBox(width: 8),
                    Text('删除书籍'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
        children: [
          _BookHero(book: widget.book),
          const SizedBox(height: 18),
          _ReadingCard(
            progress: progress,
            bookmarkCount: bookmarkCount,
            onContinue: () => _openChapter(progress?.chapterIndex ?? 0),
            onStartOver: progress == null ? null : () => _openChapter(0),
          ),
          const SizedBox(height: 22),
          SectionLabel(
            title: '章节目录',
            trailing: Text(
              '${widget.book.chapters.length} 章',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 11),
          _buildChapterPreview(context, progress?.chapterIndex),
          const SizedBox(height: 22),
          SectionLabel(
            title: '翻译设置',
            trailing: StatusPill(
              label: settings.isCurrentProviderConfigured ? '接口已就绪' : '可选功能',
              icon: settings.isCurrentProviderConfigured
                  ? Icons.check_circle_rounded
                  : Icons.key_off_outlined,
              tone: settings.isCurrentProviderConfigured
                  ? StatusTone.success
                  : StatusTone.warning,
            ),
          ),
          const SizedBox(height: 11),
          _buildTranslationCard(context, settings, thisJob, anotherJobRunning),
          const SizedBox(height: 22),
          _MultilingualDedupeCard(onTap: _openDedupe),
        ],
      ),
    );
  }

  Widget _buildTranslationCard(
    BuildContext context,
    SettingsController settings,
    TranslationJobState? thisJob,
    bool anotherJobRunning,
  ) {
    final isTranslating = thisJob != null;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _LanguageField(
                  label: '原文',
                  language: _sourceLanguage,
                  enabled: !isTranslating && !_starting,
                  onTap: _pickSourceLanguage,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: const BoxDecoration(
                    color: AppColors.paper,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: AppColors.accent,
                  ),
                ),
              ),
              Expanded(
                child: _LanguageField(
                  label: '译文',
                  language: _targetLanguage,
                  enabled: !isTranslating && !_starting,
                  onTap: _pickTargetLanguage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ApiSettingsScreen(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Icon(
                    Icons.dns_outlined,
                    size: 15,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      settings.isCurrentProviderConfigured
                          ? '${settings.provider.name} · 密钥已保存在安全存储'
                          : '尚未配置翻译接口',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Text(
                    settings.isCurrentProviderConfigured ? '管理' : '去配置',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: _recordLoading
                ? const _CheckingTranslation()
                : thisJob != null
                ? _buildProgress(thisJob)
                : _starting
                ? const _PreparingTranslation()
                : _buildActions(context, settings, anotherJobRunning),
          ),
          if (_record != null && !_recordLoading && !isTranslating) ...[
            const SizedBox(height: 12),
            _TranslationStamp(record: _record!),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress(TranslationJobState job) {
    return Padding(
      key: const ValueKey('progress'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                job.cancelRequested ? '正在停止…' : '正在翻译',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${job.percent}%',
                style: const TextStyle(
                  fontFamily: AppTheme.serif,
                  fontFamilyFallback: AppTheme.serifFallback,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: job.totalChunks == 0 ? null : job.fraction,
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '已完成 ${job.completedChunks} / ${job.totalChunks} 段 · ${job.currentChapterTitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: job.cancelRequested
                ? null
                : () =>
                      context.read<TranslationController>().cancelTranslation(),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: Text(job.cancelRequested ? '正在停止' : '取消翻译'),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    SettingsController settings,
    bool anotherJobRunning,
  ) {
    final disabled =
        _recordLoading || _starting || anotherJobRunning || _exporting;

    if (_record != null) {
      return Column(
        key: const ValueKey('actions'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _openChapter(0),
            icon: const Icon(Icons.chrome_reader_mode_outlined, size: 19),
            label: const Text('阅读译文'),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: disabled ? null : _exportTranslation,
                  icon: _exporting
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined, size: 18),
                  label: Text(_exporting ? '准备中…' : '导出译文'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: disabled ? null : _startTranslation,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新翻译'),
                ),
              ),
            ],
          ),
          if (!settings.isCurrentProviderConfigured)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '重新翻译前，请先配置翻译接口。',
                style: TextStyle(fontSize: 11, color: AppColors.gold),
              ),
            ),
          if (anotherJobRunning)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '另一本书正在翻译，完成或取消后才能开始新任务。',
                style: TextStyle(fontSize: 11, color: AppColors.gold),
              ),
            ),
        ],
      );
    }

    return Column(
      key: const ValueKey('empty-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: disabled ? null : _startTranslation,
          icon: const Icon(Icons.auto_awesome_rounded, size: 19),
          label: const Text('开始翻译'),
        ),
        const SizedBox(height: 9),
        Text(
          settings.isCurrentProviderConfigured
              ? '整书按 1800 字符分段串行翻译，免费接口更稳定。'
              : '开始后会引导你配置有道智云免费接口。',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            height: 1.5,
            color: AppColors.muted,
          ),
        ),
        if (anotherJobRunning)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '另一本书正在翻译，请稍后再试。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.gold),
            ),
          ),
      ],
    );
  }

  Widget _buildChapterPreview(BuildContext context, int? currentIndex) {
    final total = widget.book.chapters.length;
    final previewCount = math.min(8, total);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var index = 0; index < previewCount; index++) ...[
            if (index > 0) const Divider(),
            Container(
              color: currentIndex == index
                  ? AppColors.accentWash.withValues(alpha: 0.45)
                  : Colors.transparent,
              child: _ChapterRow(
                chapter: widget.book.chapters[index],
                translated:
                    _record?.chapterFor(widget.book.chapters[index].id) != null,
                onTap: () => _openChapter(index),
              ),
            ),
          ],
          if (total > previewCount) ...[
            const Divider(),
            InkWell(
              onTap: _showAllChapters,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.unfold_more_rounded,
                      size: 17,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '查看全部 $total 章',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      currentIndex == null
                          ? '尚未开始'
                          : '读到第 ${currentIndex + 1} 章',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.progress,
    required this.bookmarkCount,
    required this.onContinue,
    this.onStartOver,
  });

  final ReadingProgress? progress;
  final int bookmarkCount;
  final VoidCallback onContinue;
  final VoidCallback? onStartOver;

  @override
  Widget build(BuildContext context) {
    final reading = progress;
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2252), Color(0xFF3B2E6B)],
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const Text(
                  '阅读',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Color(0xFFD8D0F7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                reading == null ? '还没开始' : reading.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.jade,
                ),
              ),
              const Spacer(),
              Text(
                '书签 $bookmarkCount 枚',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reading == null ? '从第一章开始' : '继续读下去',
            style: const TextStyle(
              fontFamily: AppTheme.serif,
              fontFamilyFallback: AppTheme.serifFallback,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Color(0xFFF7F3FF),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            reading == null
                ? '离线阅读、精确进度和书签都会保存在本机；翻译随时可选。'
                : '累计阅读 ${formatReadingDuration(reading.readingSeconds)} · '
                      '全书 ${reading.percent}%',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          if (reading != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: reading.fraction,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.jade),
              ),
            ),
          ],
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEFEAFF),
                    foregroundColor: AppColors.paper,
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.chrome_reader_mode_outlined, size: 18),
                  label: Text(reading == null ? '开始阅读' : '继续阅读'),
                ),
              ),
              if (onStartOver != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: onStartOver,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD8D0F7),
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('从头开始'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MultilingualDedupeCard extends StatelessWidget {
  const _MultilingualDedupeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.jadeWash,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.filter_alt_outlined,
                  size: 20,
                  color: AppColors.jade,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '多语去重',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '清理日中英韩对照段落，按语言保留一边',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '生成新书',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
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

class _BookHero extends StatelessWidget {
  const _BookHero({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final isEpub = book.meta.format == BookFormat.epub;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF262143), Color(0xFF302852)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 6,
              color: isEpub ? AppColors.jade : AppColors.accent,
            ),
          ),
          Positioned(
            right: -12,
            bottom: -26,
            child: Text(
              '文',
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontFamilyFallback: AppTheme.serifFallback,
                fontSize: 128,
                height: 1,
                color: AppColors.accent.withValues(alpha: 0.055),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'book-cover-${book.id}',
                  child: BookCover(
                    title: book.title,
                    format: book.meta.format,
                    width: 66,
                    height: 88,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FormatBadge(
                            label: book.meta.format.label,
                            isEpub: isEpub,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '本地藏书 · 导入于 ${formatDate(book.meta.importedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.serif,
                          fontFamilyFallback: AppTheme.serifFallback,
                          fontSize: 24,
                          height: 1.32,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _HeroMetric(
                            value: '${book.meta.chapterCount}',
                            label: '章',
                          ),
                          const SizedBox(width: 18),
                          _HeroMetric(
                            value: formatCharacterCount(book.meta.charCount),
                            label: '字',
                          ),
                        ],
                      ),
                    ],
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

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTheme.serif,
            fontFamilyFallback: AppTheme.serifFallback,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _LanguageField extends StatelessWidget {
  const _LanguageField({
    required this.label,
    required this.language,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final AppLanguage language;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      language.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: enabled ? AppColors.ink : AppColors.muted,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: enabled ? AppColors.accent : AppColors.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranslationStamp extends StatelessWidget {
  const _TranslationStamp({required this.record});

  final TranslationRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.jadeWash.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: AppColors.jade,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${record.target.label}译文 · ${record.chapters.length} 章 · ${formatDateTime(record.createdAt)}',
              style: const TextStyle(fontSize: 11, color: AppColors.jade),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparingTranslation extends StatelessWidget {
  const _PreparingTranslation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('preparing'),
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            '正在准备分章与密钥…',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _CheckingTranslation extends StatelessWidget {
  const _CheckingTranslation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('checking'),
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            '正在查看已有译文…',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.translated,
    required this.onTap,
  });

  final BookChapter chapter;
  final bool translated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 27,
              child: Text(
                (chapter.index + 1).toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontFamily: AppTheme.serif,
                  fontFamilyFallback: AppTheme.serifFallback,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
              ),
            ),
            if (translated) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.jade,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              '${formatCharacterCount(chapter.charCount)}字',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportOptionTile extends StatelessWidget {
  const _ExportOptionTile({
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
                Icons.ios_share_outlined,
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
