import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/text_utils.dart';
import '../models/book.dart';
import '../models/bookmark.dart';

/// Bottom sheet that combines the table of contents and saved bookmarks.
class ReaderContentsSheet extends StatefulWidget {
  const ReaderContentsSheet({
    super.key,
    required this.book,
    required this.currentChapterIndex,
    required this.bookmarks,
    required this.onSelectChapter,
    required this.onSelectBookmark,
    required this.onDeleteBookmark,
    this.translation,
  });

  final Book book;
  final int currentChapterIndex;
  final TranslationRecord? translation;
  final List<Bookmark> bookmarks;
  final ValueChanged<int> onSelectChapter;
  final ValueChanged<Bookmark> onSelectBookmark;
  final Future<void> Function(Bookmark bookmark) onDeleteBookmark;

  @override
  State<ReaderContentsSheet> createState() => _ReaderContentsSheetState();
}

class _ReaderContentsSheetState extends State<ReaderContentsSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _chapterController = ScrollController();
  late List<Bookmark> _bookmarks;
  int _tab = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _bookmarks = List.of(widget.bookmarks);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tab != 0) return;
      final controller = _chapterController;
      if (!controller.hasClients) return;
      final target = widget.currentChapterIndex * 58.0 - 120;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chapterController.dispose();
    super.dispose();
  }

  List<int> get _visibleChapterIndexes {
    final query = _query.trim().toLowerCase();
    final indexes = <int>[];
    for (var index = 0; index < widget.book.chapters.length; index++) {
      final chapter = widget.book.chapters[index];
      if (query.isEmpty ||
          chapter.title.toLowerCase().contains(query) ||
          '${index + 1}'.contains(query)) {
        indexes.add(index);
      }
    }
    return indexes;
  }

  void _selectChapter(int index) {
    Navigator.of(context).pop();
    widget.onSelectChapter(index);
  }

  void _selectBookmark(Bookmark bookmark) {
    Navigator.of(context).pop();
    widget.onSelectBookmark(bookmark);
  }

  Future<void> _deleteBookmark(Bookmark bookmark) async {
    await widget.onDeleteBookmark(bookmark);
    if (!mounted) return;
    setState(() => _bookmarks.removeWhere((item) => item.id == bookmark.id));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 19,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                const Text(
                  '阅读导航',
                  style: TextStyle(
                    fontFamily: AppTheme.serif,
                    fontFamilyFallback: AppTheme.serifFallback,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.list_rounded, size: 16),
                  label: Text('目录 ${widget.book.chapters.length}'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.bookmark_border_rounded, size: 16),
                  label: Text('书签 ${_bookmarks.length}'),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _tab == 0 ? _buildChapters() : _buildBookmarks()),
        ],
      ),
    );
  }

  Widget _buildChapters() {
    final indexes = _visibleChapterIndexes;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索章节标题或章节号',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: indexes.isEmpty
              ? const _SheetEmpty(
                  icon: Icons.search_off_rounded,
                  title: '没有匹配的章节',
                  description: '试试更短的关键词，或直接搜索章节号。',
                )
              : ListView.builder(
                  controller: _chapterController,
                  padding: const EdgeInsets.only(bottom: 18),
                  itemCount: indexes.length,
                  itemBuilder: (context, position) {
                    final index = indexes[position];
                    final chapter = widget.book.chapters[index];
                    final current = index == widget.currentChapterIndex;
                    final translated =
                        widget.translation?.chapterFor(chapter.id) != null;
                    return InkWell(
                      onTap: () => _selectChapter(index),
                      child: Container(
                        height: 58,
                        color: current
                            ? AppColors.accentWash.withValues(alpha: 0.6)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontFamily: AppTheme.serif,
                                  fontFamilyFallback: AppTheme.serifFallback,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: current
                                      ? AppColors.accent
                                      : AppColors.muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chapter.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: current
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: current
                                          ? AppColors.accent
                                          : AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${formatCharacterCount(chapter.charCount)} 字'
                                    '${translated ? ' · 已有译文' : ''}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (current)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 16,
                                  color: AppColors.accent,
                                ),
                              )
                            else if (translated)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.translate_rounded,
                                  size: 14,
                                  color: AppColors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBookmarks() {
    if (_bookmarks.isEmpty) {
      return const _SheetEmpty(
        icon: Icons.bookmark_add_outlined,
        title: '还没有书签',
        description: '阅读时点击右上角的书签按钮，就能把当前段落收进这里。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: _bookmarks.length,
      separatorBuilder: (_, _) => const Divider(height: 18),
      itemBuilder: (context, index) {
        final bookmark = _bookmarks[index];
        return InkWell(
          onTap: () => _selectBookmark(bookmark),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.accentWash,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bookmark_rounded,
                    size: 15,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookmark.chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        bookmark.snippet.isEmpty
                            ? '（这一段没有可预览的文字）'
                            : bookmark.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatDateTime(bookmark.createdAt),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除书签',
                  onPressed: () => _deleteBookmark(bookmark),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.55,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
