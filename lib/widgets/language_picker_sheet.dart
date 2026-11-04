import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/language.dart';

/// Bottom-sheet language chooser shared by the book detail screen.
Future<AppLanguage?> showLanguagePicker({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<AppLanguage> languages,
  required AppLanguage selected,
}) {
  return showModalBottomSheet<AppLanguage>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              ...languages.map((language) {
                final isSelected = language.code == selected.code;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected
                        ? AppColors.accentWash
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () => Navigator.of(context).pop(language),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.accentStrong
                                    : AppColors.paperDeep,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                language.isAuto
                                    ? 'A'
                                    : language.code.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.inkSoft,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    language.isAuto
                                        ? language.label
                                        : '${language.label} · ${language.nativeLabel}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  if (language.isAuto)
                                    const Text(
                                      '由翻译引擎判断原文语言',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.accent,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}
