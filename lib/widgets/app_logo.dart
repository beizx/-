import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The vermilion seal used as the in-app brand mark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Beizx的阅读器',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFA08DFF), AppColors.accentDeep],
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: const Color(0x66EDE8FF), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 6,
              top: 6,
              right: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0x66EDE8FF),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(size * 0.2),
                ),
              ),
            ),
            Text(
              '读',
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontFamilyFallback: AppTheme.serifFallback,
                fontSize: size * 0.48,
                height: 1,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFF8F5FF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
