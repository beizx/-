import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/reader_settings.dart';
import '../state/settings_controller.dart';
import '../widgets/reader_settings_panel.dart';

/// Full-page reader preference editor, reachable from the settings tab.
class ReaderSettingsScreen extends StatelessWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('阅读设置'),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(settings.resetReaderPreferences());
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ReaderSettingsPanel(
          preferences: settings.readerPreferences,
          onChanged: (next) {
            unawaited(settings.setReaderPreferences(next));
          },
        ),
      ),
    );
  }
}

/// Compact preview used on the settings tab.
class ReaderPreferenceSummary extends StatelessWidget {
  const ReaderPreferenceSummary({super.key, required this.preferences});

  final ReaderPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          icon: Icons.text_fields_rounded,
          label: '字号 ${preferences.fontSize.round()}',
        ),
        const SizedBox(width: 7),
        _Chip(
          icon: preferences.mode == ReaderMode.page
              ? Icons.menu_book_rounded
              : Icons.swap_vert_rounded,
          label: preferences.mode.label,
        ),
        const SizedBox(width: 7),
        _Chip(icon: Icons.palette_outlined, label: preferences.skin.label),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
