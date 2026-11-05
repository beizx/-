import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/language.dart';
import 'package:translation_app/services/local_store.dart';
import 'package:translation_app/services/translation/translation_engine.dart';
import 'package:translation_app/state/translation_controller.dart';

class _Engine implements TranslationEngine {
  _Engine(this.onTranslate);

  final Future<String> Function(String text) onTranslate;
  int calls = 0;
  bool closed = false;

  @override
  String get id => 'fake';

  @override
  String get displayName => '测试';

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    calls++;
    return onTranslate(text);
  }

  @override
  void close() {
    closed = true;
  }
}

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_job',
      title: '任务书',
      author: '未知作者',
      fileName: '任务书.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 12,
      importedAt: DateTime(2026, 11, 5),
    ),
    chapters: const [
      BookChapter(id: 'chapter_0', index: 0, title: '第一章', text: '第一段文字。'),
      BookChapter(id: 'chapter_1', index: 1, title: '第二章', text: '第二段文字。'),
    ],
  );
}

void main() {
  late Directory root;
  late LocalStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('translation_job_');
    store = LocalStore(root);
    await store.ensureReady();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('cancel persists the finished chunk and resume skips it', () async {
    final controller = TranslationController(store: store);
    final first = _Engine((text) async {
      controller.cancelTranslation();
      return '译：$text';
    });

    final cancelled = await controller.startTranslation(
      book: _book(),
      sourceLanguage: Languages.zh,
      targetLanguage: Languages.ja,
      engine: first,
    );

    expect(cancelled, isNull);
    expect(controller.activeJob?.status, TranslationJobStatus.cancelled);
    expect(first.calls, 1);
    expect(first.closed, isTrue);

    final draft = await store.loadDraft('book_job', 'ja');
    expect(draft, isNotNull);
    expect(draft!.succeeded, 1);
    final partial = await store.loadTranslation('book_job', 'ja');
    expect(partial, isNotNull);
    expect(partial!.complete, isFalse);
    expect(partial.chapters, hasLength(1));

    controller.clearFinishedJob();
    final second = _Engine((text) async => '续：$text');
    final record = await controller.startTranslation(
      book: _book(),
      sourceLanguage: Languages.zh,
      targetLanguage: Languages.ja,
      engine: second,
    );

    expect(second.calls, 1);
    expect(record, isNotNull);
    expect(record!.complete, isTrue);
    expect(record.chapters.first.text, contains('译：第一段文字'));
    expect(record.chapters.last.text, contains('续：第二段文字'));
    expect(await store.loadDraft('book_job', 'ja'), isNull);
    expect(controller.activeJob?.status, TranslationJobStatus.completed);
  });

  test('a failed chunk can be retried without repeating successes', () async {
    final controller = TranslationController(store: store);
    final failing = _Engine((text) async {
      if (text.contains('第二')) {
        throw const TranslationException('bad signature', code: '202');
      }
      return '译：$text';
    });

    final first = await controller.startTranslation(
      book: _book(),
      sourceLanguage: Languages.zh,
      targetLanguage: Languages.en,
      engine: failing,
    );
    expect(first, isNull);
    expect(controller.activeJob?.status, TranslationJobStatus.partial);
    expect(failing.calls, 2);
    final draft = await controller.loadDraft('book_job', 'en');
    expect(draft?.onlyFailuresRemain, isTrue);

    controller.clearFinishedJob();
    final retry = _Engine((text) async => '修好：$text');
    final record = await controller.startTranslation(
      book: _book(),
      sourceLanguage: Languages.zh,
      targetLanguage: Languages.en,
      engine: retry,
      retryFailuresOnly: true,
    );

    expect(retry.calls, 1);
    expect(record?.complete, isTrue);
    expect(record?.chapters.first.text, contains('译：第一段文字'));
    expect(record?.chapters.last.text, contains('修好：第二段文字'));
  });
}
