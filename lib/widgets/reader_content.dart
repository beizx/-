import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/text_utils.dart';
import '../models/reader_settings.dart';
import '../services/reader/reader_paginator.dart';

TextStyle readerBodyStyle(ReaderPreferences reader) {
  return TextStyle(
    fontFamily: reader.serif ? AppTheme.serif : null,
    fontFamilyFallback: reader.serif ? AppTheme.serifFallback : null,
    fontSize: reader.fontSize,
    height: reader.lineHeight,
    fontWeight: reader.fontWeight.fontWeight,
    letterSpacing: 0.25,
    color: reader.skin.text,
  );
}

TextStyle readerTitleStyle(ReaderPreferences reader) {
  return TextStyle(
    fontFamily: AppTheme.serif,
    fontFamilyFallback: AppTheme.serifFallback,
    fontSize: reader.fontSize + 7,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: reader.skin.text,
  );
}

/// Vertical scroll reader for one chapter. Taps toggle the chrome; scrolling
/// reports a 0..1 position so the parent can persist the exact spot.
class ReaderScrollView extends StatefulWidget {
  const ReaderScrollView({
    super.key,
    required this.chapterTitle,
    required this.text,
    required this.isTranslation,
    required this.reader,
    required this.contentPadding,
    required this.initialFraction,
    required this.onFractionChanged,
    required this.onToggleChrome,
    required this.hasNextChapter,
  });

  final String chapterTitle;
  final String text;
  final bool isTranslation;
  final ReaderPreferences reader;
  final EdgeInsets contentPadding;
  final double initialFraction;
  final ValueChanged<double> onFractionChanged;
  final VoidCallback onToggleChrome;
  final bool hasNextChapter;

  @override
  State<ReaderScrollView> createState() => _ReaderScrollViewState();
}

class _ReaderScrollViewState extends State<ReaderScrollView> {
  final ScrollController _controller = ScrollController();
  Offset? _downPosition;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  void _restore() {
    if (!mounted) return;
    if (_controller.hasClients) {
      final max = _controller.position.maxScrollExtent;
      if (max > 0 && widget.initialFraction > 0.001) {
        _controller.jumpTo((widget.initialFraction * max).clamp(0.0, max));
      }
    }
    _restored = true;
  }

  void _handleScroll() {
    if (!_restored || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final fraction = max <= 0
        ? 1.0
        : (_controller.offset / max).clamp(0.0, 1.0);
    widget.onFractionChanged(fraction);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    final skin = reader.skin;
    final paragraphs = ReaderPaginator.displayParagraphs(
      widget.text,
      firstLineIndent: reader.firstLineIndent,
    );
    final bodyStyle = readerBodyStyle(reader);
    final align = reader.justify ? TextAlign.justify : TextAlign.start;

    return Listener(
      onPointerDown: (event) => _downPosition = event.position,
      onPointerUp: (event) {
        final start = _downPosition;
        _downPosition = null;
        if (start == null) return;
        if ((event.position - start).distance > 12) return;
        widget.onToggleChrome();
      },
      child: SingleChildScrollView(
        controller: _controller,
        padding: widget.contentPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.chapterTitle, style: readerTitleStyle(reader)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 2,
                        color: skin.accent.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.isTranslation
                            ? '机器翻译 · 建议对照原文阅读'
                            : '${formatCharacterCount(widget.text.runes.length)}字',
                        style: TextStyle(fontSize: 10.5, color: skin.secondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (paragraphs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          widget.isTranslation ? '这一章暂时没有译文' : '这一章没有正文',
                          style: TextStyle(fontSize: 13, color: skin.secondary),
                        ),
                      ),
                    )
                  else
                    for (final paragraph in paragraphs)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: reader.paragraphSpacing,
                        ),
                        child: Text(
                          paragraph,
                          style: bodyStyle,
                          textAlign: align,
                        ),
                      ),
                  const SizedBox(height: 26),
                  Center(
                    child: Column(
                      children: [
                        Container(width: 36, height: 1, color: skin.line),
                        const SizedBox(height: 10),
                        Text(
                          '本章完',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 3,
                            color: skin.secondary,
                          ),
                        ),
                        if (widget.hasNextChapter) ...[
                          const SizedBox(height: 4),
                          Text(
                            '左右滑动进入下一章',
                            style: TextStyle(
                              fontSize: 10,
                              color: skin.secondary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paginated reader for one chapter. A leading and trailing sentinel page let
/// the reader swipe into the adjacent chapters naturally.
class ReaderPageView extends StatefulWidget {
  const ReaderPageView({
    super.key,
    required this.chapterTitle,
    required this.text,
    required this.isTranslation,
    required this.reader,
    required this.contentPadding,
    required this.initialFraction,
    required this.onFractionChanged,
    required this.onToggleChrome,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
    required this.onPreviousChapter,
    required this.onNextChapter,
    this.selectable = false,
  });

  final String chapterTitle;
  final String text;
  final bool isTranslation;
  final ReaderPreferences reader;
  final EdgeInsets contentPadding;
  final double initialFraction;
  final ValueChanged<double> onFractionChanged;
  final VoidCallback onToggleChrome;
  final bool hasPreviousChapter;
  final bool hasNextChapter;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;

  /// Text selection is enabled while the toolbar is visible. The default
  /// immersive state keeps horizontal drags free for page turning.
  final bool selectable;

  @override
  State<ReaderPageView> createState() => _ReaderPageViewState();
}

class _ReaderPageViewState extends State<ReaderPageView> {
  ReaderPagination _pagination = ReaderPagination.empty;
  String _layoutKey = '';
  PageController? _controller;
  int _currentPage = 0;
  double _currentFraction = 0;
  bool _switchingChapter = false;

  @override
  void initState() {
    super.initState();
    _currentFraction = widget.initialFraction.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  int _pageForFraction(int count, double fraction) {
    if (count <= 0) return 0;
    if (fraction >= 0.999) return count - 1;
    if (fraction <= 0.001) return 0;
    return ((fraction * count).ceil() - 1).clamp(0, count - 1);
  }

  double _fractionForPage(int page, int count) {
    if (count <= 0) return 0;
    return ((page + 1) / count).clamp(0.0, 1.0);
  }

  void _ensureLayout(
    ReaderPreferences reader,
    Size size,
    TextAlign align,
    double titleHeight,
    double bodyHeight,
    TextScaler textScaler,
  ) {
    final titleKey = widget.chapterTitle;
    final key = [
      widget.text.length,
      widget.text.hashCode,
      titleKey,
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      reader.layoutSignature,
      reader.paragraphSpacing.toStringAsFixed(1),
      reader.showPageNumber,
      align.name,
      textScaler.scale(1).toStringAsFixed(3),
      widget.contentPadding.left.toStringAsFixed(1),
      widget.contentPadding.top.toStringAsFixed(1),
      widget.contentPadding.right.toStringAsFixed(1),
      widget.contentPadding.bottom.toStringAsFixed(1),
    ].join('#');

    if (key == _layoutKey) return;

    final hadLayout = _layoutKey.isNotEmpty;
    final fraction = hadLayout
        ? _currentFraction
        : widget.initialFraction.clamp(0.0, 1.0);
    final style = readerBodyStyle(reader);
    final contentWidth = size.width - widget.contentPadding.horizontal;
    final firstBodyHeight = titleHeight <= 0
        ? bodyHeight
        : math.max(bodyHeight - titleHeight - 42, 40.0);

    _pagination = ReaderPaginator.paginate(
      text: widget.text,
      textStyle: style,
      maxWidth: math.max(contentWidth, 40.0),
      pageHeight: math.max(bodyHeight, 40.0),
      firstPageHeight: firstBodyHeight,
      paragraphSpacing: reader.paragraphSpacing,
      firstLineIndent: reader.firstLineIndent,
      textAlign: align,
      textScaler: textScaler,
    );
    _layoutKey = key;
    final count = _pagination.pages.length;
    _currentPage = _pageForFraction(count, fraction);
    _currentFraction = count <= 0 ? 0 : _fractionForPage(_currentPage, count);
    if (hadLayout) {
      widget.onFractionChanged(_currentFraction);
    }

    final previousController = _controller;
    _controller = PageController(initialPage: _currentPage + 1);
    if (previousController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }
  }

  void _requestChapter(int direction) {
    if (_switchingChapter) return;
    if (direction < 0) {
      if (widget.hasPreviousChapter) {
        _switchingChapter = true;
        widget.onPreviousChapter();
      } else {
        _showEdgeHint('已经是第一页了');
        _snapBackToFirstPage();
      }
    } else {
      if (widget.hasNextChapter) {
        _switchingChapter = true;
        widget.onNextChapter();
      } else {
        _showEdgeHint('已经是最后一页了');
        _snapBackToLastPage();
      }
    }
  }

  void _showEdgeHint(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  void _snapBackToFirstPage() {
    if (_controller?.hasClients ?? false) {
      _controller!.animateToPage(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _snapBackToLastPage() {
    final count = _pagination.pages.length;
    if (count > 0 && (_controller?.hasClients ?? false)) {
      _controller!.animateToPage(
        count,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _turnPage(int direction) {
    final count = _pagination.pages.length;
    if (count == 0 || _controller == null) return;
    final targetPage = _currentPage + direction;
    if (targetPage < 0) {
      _requestChapter(-1);
      return;
    }
    if (targetPage >= count) {
      _requestChapter(1);
      return;
    }
    final target = targetPage + 1;
    if (widget.reader.turnAnimation == ReaderTurnAnimation.none) {
      _controller!.jumpToPage(target);
    } else {
      _controller!.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleTap(Offset position, Size size) {
    if (!widget.reader.tapToTurnPage) {
      widget.onToggleChrome();
      return;
    }
    if (position.dx < size.width * 0.28) {
      _turnPage(-1);
    } else if (position.dx > size.width * 0.72) {
      _turnPage(1);
    } else {
      widget.onToggleChrome();
    }
  }

  void _handlePageChanged(int index) {
    final count = _pagination.pages.length;
    if (index == 0) {
      _requestChapter(-1);
      return;
    }
    if (index == count + 1) {
      _requestChapter(1);
      return;
    }
    final realPage = (index - 1).clamp(0, math.max(count - 1, 0)).toInt();
    if (realPage == _currentPage) return;
    _currentPage = realPage;
    _currentFraction = _fractionForPage(realPage, count);
    widget.onFractionChanged(_currentFraction);
  }

  double _measureTitleHeight(
    double maxWidth,
    TextStyle style,
    TextScaler textScaler,
  ) {
    if (widget.chapterTitle.trim().isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: widget.chapterTitle, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    final skin = reader.skin;

    return LayoutBuilder(
      builder: (context, constraints) {
        final align = reader.justify ? TextAlign.justify : TextAlign.start;
        final textScaler = MediaQuery.textScalerOf(context);
        final titleHeight = _measureTitleHeight(
          math.max(constraints.maxWidth - widget.contentPadding.horizontal, 40),
          readerTitleStyle(reader),
          textScaler,
        );
        final bodyHeight =
            constraints.maxHeight -
            widget.contentPadding.vertical -
            (reader.showPageNumber ? 22 : 0);
        _ensureLayout(
          reader,
          constraints.biggest,
          align,
          titleHeight,
          bodyHeight,
          textScaler,
        );

        final pages = _pagination.pages;
        final controller = _controller;
        if (pages.isEmpty || controller == null) {
          return Center(
            child: Text(
              widget.isTranslation ? '这一章暂时没有译文' : '这一章没有正文',
              style: TextStyle(color: skin.secondary),
            ),
          );
        }

        return PageView.builder(
          key: ValueKey(_layoutKey),
          controller: controller,
          onPageChanged: _handlePageChanged,
          itemCount: pages.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _ChapterEdgePage(
                skin: skin,
                title: '已经是第一页了',
                subtitle: widget.hasPreviousChapter ? '向右滑动返回上一章' : '这里是故事的开头',
                enabled: widget.hasPreviousChapter,
                onTap: () => _requestChapter(-1),
              );
            }
            if (index == pages.length + 1) {
              return _ChapterEdgePage(
                skin: skin,
                title: '已经是最后一页了',
                subtitle: widget.hasNextChapter ? '向左滑动进入下一章' : '故事到这里结束',
                enabled: widget.hasNextChapter,
                onTap: () => _requestChapter(1),
              );
            }
            return _buildPageContent(
              context,
              index - 1,
              constraints.biggest,
              titleHeight,
            );
          },
        );
      },
    );
  }

  Widget _buildPageContent(
    BuildContext context,
    int pageIndex,
    Size size,
    double titleHeight,
  ) {
    final reader = widget.reader;
    final skin = reader.skin;
    final page = _pagination.pages[pageIndex];
    final isFirst = pageIndex == 0;
    final bodyStyle = readerBodyStyle(reader);
    final align = reader.justify ? TextAlign.justify : TextAlign.start;

    Widget? header;
    if (isFirst) {
      header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.chapterTitle, style: readerTitleStyle(reader)),
          const SizedBox(height: 10),
          SizedBox(
            height: 14,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 2,
                  color: skin.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isTranslation
                      ? '机器翻译 · 建议对照原文阅读'
                      : '${formatCharacterCount(widget.text.runes.length)}字',
                  style: TextStyle(fontSize: 10.5, color: skin.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    }

    final fragments = <Widget>[];
    for (var i = 0; i < page.fragments.length; i++) {
      final fragment = page.fragments[i];
      if (i > 0 &&
          fragment.paragraphIndex != page.fragments[i - 1].paragraphIndex) {
        fragments.add(SizedBox(height: reader.paragraphSpacing));
      }
      fragments.add(
        Text(
          fragment.textOf(_pagination.displayParagraphs),
          style: bodyStyle,
          textAlign: align,
        ),
      );
    }
    final contentWidth = size.width - widget.contentPadding.horizontal;
    final pageBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [?header, ...fragments],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _handleTap(details.localPosition, size),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: widget.contentPadding,
              // A plain clipped column keeps horizontal drags available to the
              // surrounding PageView; a nested scroll view would swallow them.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  maxWidth: contentWidth,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: SizedBox(
                    width: contentWidth,
                    child: widget.selectable
                        ? SelectionArea(child: pageBody)
                        : pageBody,
                  ),
                ),
              ),
            ),
          ),
          if (reader.showPageNumber)
            Positioned(
              left: widget.contentPadding.left,
              right: widget.contentPadding.right,
              bottom: math.max(
                widget.contentPadding.bottom - 22,
                MediaQuery.paddingOf(context).bottom + 30,
              ),
              child: Center(
                child: Text(
                  '第 ${pageIndex + 1} / ${_pagination.pages.length} 页',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: skin.secondary.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterEdgePage extends StatelessWidget {
  const _ChapterEdgePage({
    required this.skin,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final ReaderSkin skin;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 30,
                color: skin.secondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppTheme.serif,
                  fontFamilyFallback: AppTheme.serifFallback,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: skin.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: skin.secondary),
              ),
              if (enabled) ...[
                const SizedBox(height: 16),
                Icon(
                  Icons.keyboard_double_arrow_right_rounded,
                  size: 19,
                  color: skin.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
