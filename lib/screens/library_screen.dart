import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation/app_page_route.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/reading_progress.dart';
import '../screens/book_detail_screen.dart';
import '../screens/chapter_reader_screen.dart';
import '../services/import/book_importer.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../state/translation_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/book_cover.dart';
import '../widgets/common_widgets.dart';

enum _LibraryFilter { all, txt, epub }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _LibraryFilter _filter = _LibraryFilter.all;
  String? _openingBookId;

  Future<void> _importBook() async {
    final library = context.read<LibraryController>();
    if (library.isImporting) return;
    try {
      final book = await library.importBook();
      if (!mounted || book == null) return;
      await _openBook(book.meta, preselect: book);
    } on BookImportException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object catch (error) {
      if (mounted) _showMessage('导入失败：$error');
    }
  }

  Future<Book?> _loadBook(BookMeta meta, {Book? preselect}) async {
    if (preselect != null) return preselect;
    return context.read<LibraryController>().openBook(meta.id);
  }

  Future<void> _openBook(BookMeta meta, {Book? preselect}) async {
    if (_openingBookId != null) return;
    setState(() => _openingBookId = meta.id);
    try {
      final book = await _loadBook(meta, preselect: preselect);
      if (!mounted) return;
      if (book == null) {
        _showMessage('书籍文件已损坏或不存在');
        return;
      }
      await Navigator.of(context).push(
        CoverExpandRoute<void>(builder: (_) => BookDetailScreen(book: book)),
      );
    } finally {
      if (mounted) setState(() => _openingBookId = null);
    }
  }

  /// Opens the reader straight at the saved chapter, without detouring
  /// through the detail page.
  Future<void> _continueReading(BookMeta meta) async {
    if (_openingBookId != null) return;
    setState(() => _openingBookId = meta.id);
    try {
      final book = await _loadBook(meta);
      if (!mounted) return;
      if (book == null) {
        _showMessage('书籍文件已损坏或不存在');
        return;
      }
      final progress = context.read<LibraryController>().progressFor(meta.id);
      final targetLanguage = context.read<SettingsController>().targetLanguage;
      final translation = await context
          .read<TranslationController>()
          .loadTranslation(meta.id, targetLanguage.code);
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ChapterReaderScreen(
            book: book,
            initialChapterIndex: progress?.chapterIndex ?? 0,
            translation: translation,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingBookId = null);
    }
  }

  Future<void> _showShelfActions(BookMeta meta) async {
    final progress = context.read<LibraryController>().progressFor(meta.id);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.serif,
                          fontFamilyFallback: AppTheme.serifFallback,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _ShelfAction(
                icon: Icons.chrome_reader_mode_outlined,
                label: progress == null ? '开始阅读' : '继续阅读 · ${progress.label}',
                onTap: () {
                  Navigator.of(context).pop();
                  _continueReading(meta);
                },
              ),
              _ShelfAction(
                icon: Icons.info_outline_rounded,
                label: '书籍详情',
                onTap: () {
                  Navigator.of(context).pop();
                  _openBook(meta);
                },
              ),
              _ShelfAction(
                icon: Icons.delete_outline_rounded,
                label: '移出书架',
                danger: true,
                onTap: () {
                  Navigator.of(context).pop();
                  _deleteBook(meta);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteBook(BookMeta meta) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出书架？'),
        content: Text('《${meta.title}》的本地原书和所有已完成的译文都会被删除。此操作无法撤销。'),
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

    await context.read<LibraryController>().deleteBook(meta.id);
    if (!mounted) return;
    context.read<TranslationController>().evictBook(meta.id);
    _showMessage('《${meta.title}》已移出书架');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<BookMeta> _visibleBooks(List<BookMeta> books) {
    return switch (_filter) {
      _LibraryFilter.all => books,
      _LibraryFilter.txt =>
        books.where((book) => book.format == BookFormat.txt).toList(),
      _LibraryFilter.epub =>
        books.where((book) => book.format == BookFormat.epub).toList(),
    };
  }

  /// The most recently opened book, shown as "continue reading" when present.
  BookMeta? _resumeTarget(LibraryController library) {
    final progress = library.readingProgress.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final entry in progress) {
      for (final meta in library.books) {
        if (meta.id == entry.bookId) return meta;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final books = _visibleBooks(library.books);
    final resume = _resumeTarget(library);
    final resumeProgress = resume == null
        ? null
        : library.progressFor(resume.id);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: library.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeader(context),
                    const SizedBox(height: 18),
                    _ImportHero(
                      isImporting: library.isImporting,
                      onImport: _importBook,
                    ),
                    if (library.loadError != null) ...[
                      const SizedBox(height: 14),
                      InfoNote(
                        text: library.loadError!,
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.danger,
                        background: AppColors.dangerWash,
                      ),
                    ],
                    if (resume != null && resumeProgress != null) ...[
                      const SizedBox(height: 16),
                      _ResumeCard(
                        meta: resume,
                        progress: resumeProgress,
                        busy: _openingBookId == resume.id,
                        onContinue: () => _continueReading(resume),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SectionLabel(
                      title: '我的书架',
                      trailing: Text(
                        '共 ${library.bookCount} 本 · '
                        '书签 ${library.bookmarkCount} 枚',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFilters(),
                    const SizedBox(height: 14),
                  ]),
                ),
              ),
              if (library.isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 62),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (library.books.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(child: _EmptyLibrary()),
                )
              else if (books.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(child: _FilteredEmpty()),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 118,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 20,
                          childAspectRatio: 0.49,
                        ),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final meta = books[index];
                      return _ShelfBook(
                        meta: meta,
                        progress: library.progressFor(meta.id),
                        busy: _openingBookId == meta.id,
                        onTap: () => _openBook(meta),
                        onContinue: () => _continueReading(meta),
                        onLongPress: () => _showShelfActions(meta),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const AppLogo(size: 48),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Beizx的阅读器',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 23,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '读一本小说，也读它的另一种语言',
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 0.5,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        Material(
          color: AppColors.card,
          shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
          child: IconButton(
            tooltip: '设置',
            onPressed: widget.onOpenSettings,
            icon: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    Widget chip(_LibraryFilter filter, String label) {
      return ChoiceChip(
        label: Text(label),
        selected: _filter == filter,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = filter),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 7,
            children: [
              chip(_LibraryFilter.all, '全部'),
              chip(_LibraryFilter.txt, 'TXT'),
              chip(_LibraryFilter.epub, 'EPUB'),
            ],
          ),
        ),
      ],
    );
  }
}

/// A shelf tile: cover with a thin progress line, title and reading state.
class _ShelfBook extends StatelessWidget {
  const _ShelfBook({
    required this.meta,
    required this.progress,
    required this.busy,
    required this.onTap,
    required this.onContinue,
    required this.onLongPress,
  });

  final BookMeta meta;
  final ReadingProgress? progress;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onContinue;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final reading = progress;
    return GestureDetector(
      onTap: busy ? null : onTap,
      onLongPress: busy ? null : onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'book-cover-${meta.id}',
                  child: BookCover(title: meta.title, format: meta.format),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: reading?.fraction ?? 0,
                      minHeight: 3,
                      backgroundColor: Colors.black.withValues(alpha: 0.32),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.jade,
                      ),
                    ),
                  ),
                ),
                if (busy)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: busy ? null : onContinue,
            child: Text(
              reading == null
                  ? '${meta.chapterCount} 章 · ${meta.format.label}'
                  : reading.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: reading == null ? AppColors.muted : AppColors.jade,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.meta,
    required this.progress,
    required this.busy,
    required this.onContinue,
  });

  final BookMeta meta;
  final ReadingProgress progress;
  final bool busy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onContinue,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2252), Color(0xFF3B2E6B)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Hero(
                tag: 'book-cover-${meta.id}-resume',
                child: BookCover(
                  title: meta.title,
                  format: meta.format,
                  width: 44,
                  height: 58,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '继续阅读',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: AppColors.jade,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.serif,
                        fontFamilyFallback: AppTheme.serifFallback,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress.label,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.accentStrong,
                  shape: BoxShape.circle,
                ),
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfAction extends StatelessWidget {
  const _ShelfAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 19, color: color),
      title: Text(label, style: TextStyle(fontSize: 14, color: color)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _ImportHero extends StatelessWidget {
  const _ImportHero({required this.isImporting, required this.onImport});

  final bool isImporting;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2252), Color(0xFF43306F)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -16,
              child: Text(
                '读',
                style: TextStyle(
                  fontFamily: AppTheme.serif,
                  fontFamilyFallback: AppTheme.serifFallback,
                  fontSize: 132,
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.055),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Text(
                          '导入',
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
                        'TXT / EPUB',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: Colors.white.withValues(alpha: 0.52),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '把一本小说留在书架',
                    style: TextStyle(
                      fontFamily: AppTheme.serif,
                      fontFamilyFallback: AppTheme.serifFallback,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: Color(0xFFF7F3FF),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '导入后自动上架，离线也能读；需要时再把整本书交给翻译。文件只留在本机。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 17),
                  FilledButton.icon(
                    onPressed: isImporting ? null : onImport,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEFEAFF),
                      foregroundColor: AppColors.paper,
                      minimumSize: const Size(0, 45),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    icon: isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentStrong,
                            ),
                          )
                        : const Icon(Icons.add_rounded, size: 19),
                    label: Text(isImporting ? '正在解析文件…' : '导入书籍'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: const BoxDecoration(
                  color: AppColors.accentWash,
                  shape: BoxShape.circle,
                ),
              ),
              Transform.rotate(
                angle: -0.08,
                child: Container(
                  width: 43,
                  height: 57,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 21,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Text('书架还空着', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            '从一段文字开始。导入 TXT 或 EPUB，\n书会留在书架上，离线也能读，翻译随时可选。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.65,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: const Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, color: AppColors.muted, size: 27),
          SizedBox(height: 8),
          Text(
            '这个格式下还没有书',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
