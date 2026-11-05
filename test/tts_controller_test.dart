import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/models/tts_settings.dart';
import 'package:translation_app/state/tts_controller.dart';

import 'support/fake_speech_engine.dart';

Book _book({String chapters = 'two'}) {
  final list = <BookChapter>[
    const BookChapter(
      id: 'c0',
      index: 0,
      title: '第一章 起雾',
      text: '海面起了雾。\n\n灯塔仍亮着。',
    ),
  ];
  if (chapters == 'two') {
    list.add(
      const BookChapter(id: 'c1', index: 1, title: '第二章 归航', text: '船在清晨靠岸。'),
    );
  }
  return Book(
    meta: BookMeta(
      id: 'book_tts',
      title: '听书测试',
      author: '未知',
      fileName: '听书测试.txt',
      format: BookFormat.txt,
      chapterCount: list.length,
      charCount: 40,
      importedAt: DateTime(2026, 11, 5),
    ),
    chapters: list,
  );
}

void main() {
  group('TtsController segmentation', () {
    test('splits paragraphs and keeps chapter offsets', () {
      const text = '第一段。\n\n第二段。';
      final segments = TtsController.buildSegments(text);
      expect(segments.map((segment) => segment.text), ['第一段。', '第二段。']);
      expect(segments[0].paragraphIndex, 0);
      expect(segments[1].paragraphIndex, 1);
      for (final segment in segments) {
        expect(
          text.substring(segment.start, segment.end),
          segment.text,
          reason: 'offset must point at the utterance inside the chapter',
        );
      }
    });

    test('long paragraphs split at sentence punctuation', () {
      final sentence = '这是很长的一句话，用来测试分段逻辑。';
      final text = List.filled(40, sentence).join();
      final segments = TtsController.buildSegments(text);
      expect(segments.length, greaterThan(1));
      for (final segment in segments) {
        expect(segment.text.length, lessThanOrEqualTo(TtsController.maxSegmentLength));
        expect(segment.text.endsWith('。'), isTrue);
      }
      expect(segments.map((segment) => segment.text).join(), text);
    });

    test('text without punctuation still splits at the hard limit', () {
      final text = 'a' * (TtsController.maxSegmentLength * 2 + 10);
      final segments = TtsController.buildSegments(text);
      expect(segments.length, 3);
      expect(segments.first.text.length, TtsController.maxSegmentLength);
    });

    test('empty text yields no segments', () {
      expect(TtsController.buildSegments('   \n\n  '), isEmpty);
    });
  });

  group('TtsController playback', () {
    late FakeSpeechEngine engine;
    late TtsController controller;

    setUp(() {
      engine = FakeSpeechEngine();
      controller = TtsController(engine: engine);
    });

    tearDown(() => controller.dispose());

    test('startChapter speaks the first segment', () async {
      await controller.startChapter(_book(), 0);
      expect(controller.status, TtsStatus.playing);
      expect(engine.lastSpoken, '海面起了雾。');
      expect(controller.chapterTitle, '第一章 起雾');
      expect(engine.prepared.single.rate, const TtsPreferences().rate);
    });

    test('completion advances through segments inside one chapter', () async {
      await controller.startChapter(_book(), 0);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      expect(controller.segmentIndex, 1);
      expect(engine.lastSpoken, '灯塔仍亮着。');
    });

    test('auto next chapter keeps reading after the last segment', () async {
      await controller.startChapter(_book(), 0);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.chapterIndex, 1);
      expect(engine.lastSpoken, '船在清晨靠岸。');
      expect(controller.isPlaying, isTrue);
    });

    test('disabling auto next chapter stops at the chapter end', () async {
      await controller.updatePreferences(
        controller.preferences.copyWith(autoNextChapter: false),
      );
      await controller.startChapter(_book(), 0);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      expect(controller.chapterIndex, 0);
      expect(controller.status, TtsStatus.idle);
    });

    test('sleep at chapter end stops instead of continuing', () async {
      controller.setSleepTimer(atChapterEnd: true);
      await controller.startChapter(_book(), 0);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      engine.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      expect(controller.chapterIndex, 0);
      expect(controller.status, TtsStatus.idle);
      expect(controller.sleepAtChapterEnd, isTrue);
    });

    test('pause and resume toggle the status', () async {
      await controller.startChapter(_book(), 0);
      await controller.pause();
      expect(controller.status, TtsStatus.paused);
      expect(engine.pauseCalls, 1);
      await controller.resume();
      expect(controller.status, TtsStatus.playing);
      expect(engine.spoken.length, 2);
    });

    test('skipSegment crosses chapter boundaries', () async {
      await controller.startChapter(_book(), 0);
      await controller.skipSegment(1);
      expect(engine.lastSpoken, '灯塔仍亮着。');
      await controller.skipSegment(1);
      expect(controller.chapterIndex, 1);
      expect(engine.lastSpoken, '船在清晨靠岸。');
      await controller.skipSegment(-1);
      expect(controller.chapterIndex, 0);
      expect(engine.lastSpoken, '灯塔仍亮着。');
    });

    test('skipChapter moves between chapters', () async {
      await controller.startChapter(_book(), 0);
      await controller.skipChapter(1);
      expect(controller.chapterIndex, 1);
      await controller.skipChapter(-1);
      expect(controller.chapterIndex, 0);
    });

    test('startChapter with a fraction resumes mid-chapter', () async {
      final book = Book(
        meta: _book().meta,
        chapters: [
          BookChapter(
            id: 'long',
            index: 0,
            title: '长章',
            text: List.generate(10, (index) => '第 $index 段。').join('\n\n'),
          ),
        ],
      );
      await controller.startChapter(book, 0, chapterFraction: 0.5);
      expect(controller.segmentIndex, 5);
      expect(engine.lastSpoken, '第 5 段。');
    });

    test('empty chapter reports an error instead of speaking', () async {
      final book = Book(
        meta: _book().meta,
        chapters: const [
          BookChapter(id: 'blank', index: 0, title: '空章', text: '   '),
        ],
      );
      await controller.startChapter(book, 0);
      expect(controller.status, TtsStatus.error);
      expect(controller.error, contains('没有可以朗读'));
      expect(engine.spoken, isEmpty);
    });

    test('engine failures surface as an error state', () async {
      engine.failOnSpeak = true;
      await controller.startChapter(_book(), 0);
      expect(controller.status, TtsStatus.error);
      expect(controller.error, contains('朗读引擎出错'));
    });

    test('stop clears the session', () async {
      await controller.startChapter(_book(), 0);
      await controller.stop();
      expect(controller.status, TtsStatus.idle);
      expect(controller.book, isNull);
      expect(controller.hasContent, isFalse);
    });

    test('isReadingChapter only matches the active book and chapter', () async {
      await controller.startChapter(_book(), 1);
      expect(controller.isReadingChapter('book_tts', 1), isTrue);
      expect(controller.isReadingChapter('book_tts', 0), isFalse);
      expect(controller.isReadingChapter('other', 1), isFalse);
    });

    test('speed changes propagate to the engine', () async {
      await controller.startChapter(_book(), 0);
      await controller.updatePreferences(
        controller.preferences.copyWith(rate: 0.8),
      );
      expect(engine.prepared.last.rate, 0.8);
    });
  });

  group('TtsPreferences', () {
    test('round trips through JSON and clamps rate', () {
      const preferences = TtsPreferences(rate: 3.0, pitch: 0.1);
      final decoded = TtsPreferences.decode(preferences.encode());
      expect(decoded.rate, TtsPreferences.maxRate);
      expect(decoded.pitch, TtsPreferences.minPitch);
      expect(decoded.languageCode, 'zh-CN');
    });

    test('corrupted JSON falls back to defaults', () {
      expect(TtsPreferences.decode('{not json').rate, const TtsPreferences().rate);
    });

    test('speed labels read like a player', () {
      expect(TtsPreferences.labelForRate(0.5), '1.0x');
      expect(TtsPreferences.labelForRate(1.0), '2.0x');
      expect(TtsPreferences.labelForRate(0.35), '0.7x');
    });

    test('clearing the voice drops the name', () {
      const preferences = TtsPreferences(voiceName: 'zh-cn-x-1');
      expect(preferences.copyWith(clearVoice: true).voiceName, isNull);
    });
  });
}
