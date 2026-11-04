import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/book.dart';

/// Deterministic cover art for a book: a gradient spine card with the opening
/// character, used on the shelf and in the detail hero.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    required this.format,
    this.width,
    this.height,
    this.showFormatLabel = true,
  });

  final String title;
  final BookFormat format;
  final double? width;
  final double? height;
  final bool showFormatLabel;

  static const List<List<Color>> _palettes = [
    [Color(0xFF6E58DB), Color(0xFF3B2C7A)],
    [Color(0xFF25635E), Color(0xFF163B39)],
    [Color(0xFF8C5A8F), Color(0xFF4A2C55)],
    [Color(0xFF3E6BA8), Color(0xFF233E63)],
    [Color(0xFF9A6B3F), Color(0xFF553719)],
    [Color(0xFF4B3A96), Color(0xFF2A2050)],
  ];

  List<Color> get _palette {
    if (format == BookFormat.epub) return _palettes[1];
    var hash = 0;
    for (final unit in title.runes) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return _palettes[hash % _palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _palette;
    final initial = title.trim().isEmpty
        ? '书'
        : String.fromCharCode(title.trim().runes.first);

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 7,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1.6,
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              right: 6,
              top: 8,
              child: Text(
                format.label,
                style: TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontFamily: AppTheme.serif,
                      fontFamilyFallback: AppTheme.serifFallback,
                      fontSize: 46,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF8F5FF),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
