import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/models/book.dart';
import 'package:translation_app/state/tts_controller.dart';

import 'support/fake_media_session.dart';
import 'support/fake_speech_engine.dart';

Book _book() {
  return Book(
    meta: BookMeta(
      id: 'book_media',
      title: '锁屏测试',
      author: '未知',
      fileName: '锁屏测试.txt',
      format: BookFormat.txt,
      chapterCount: 2,
      charCount: 40,
      importedAt: DateTime(2026, 11, 5),
    ),
    chapters: const [
      BookChapter(id: 'c0', index: 0, title: '第一章 起雾', text: '海面起了雾。\n\n灯塔仍亮着。'),
      BookChapter(id: 'c1', index: 1, title: '第二章 归航', text: '船在清晨靠岸。'),
    ],
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSpeechEngine engine;
  late FakeMediaSession media;
  late TtsController controller;

  setUp(() {
    engine = FakeSpeechEngine();
    media = FakeMediaSession();
    controller = TtsController(engine: engine, mediaSession: media);
  });

  tearDown(() => controller.dispose());

  group('TtsController media session', () {
    test('publishes the chapter to the lock screen on start', () async {
      await controller.startChapter(_book(), 0);
      await _settle();

      final info = media.last;
      expect(info, isNotNull);
      expect(info!.bookTitle, '锁屏测试');
      expect(info.chapterTitle, '第一章 起雾');
      expect(info.isPlaying, isTrue);
      expect(info.canSkipPrevious, isFalse);
      expect(info.canSkipNext, isTrue);
    });

    test('pause and resume keep the media UI in sync', () async {
      await controller.startChapter(_book(), 0);
      await controller.pause();
      await _settle();
      expect(media.last?.isPlaying, isFalse);

      await controller.resume();
      await _settle();
      expect(media.last?.isPlaying, isTrue);
    });

    test('lock screen play / pause drive the controller', () async {
      await controller.startChapter(_book(), 0);
      final commands = media.commands!;

      await commands.onPause();
      expect(controller.status, TtsStatus.paused);
      await _settle();
      expect(media.last?.isPlaying, isFalse);

      await commands.onPlay();
      expect(controller.status, TtsStatus.playing);
      await _settle();
      expect(media.last?.isPlaying, isTrue);
    });

    test('next / previous move between chapters', () async {
      await controller.startChapter(_book(), 0);
      final commands = media.commands!;

      await commands.onNext();
      await _settle();
      expect(controller.chapterIndex, 1);
      expect(media.last?.chapterTitle, '第二章 归航');
      expect(media.last?.canSkipNext, isFalse);

      await commands.onPrevious();
      await _settle();
      expect(controller.chapterIndex, 0);
      expect(media.last?.chapterTitle, '第一章 起雾');
    });

    test('stop removes the notification', () async {
      await controller.startChapter(_book(), 0);
      await media.commands!.onStop();
      await _settle();

      expect(controller.status, TtsStatus.idle);
      expect(controller.book, isNull);
      expect(media.clearCalls, 1);
    });

    test('does not republish unchanged state for every sentence', () async {
      await controller.startChapter(_book(), 0);
      await _settle();
      final published = media.updates.length;

      engine.finishCurrent();
      await _settle();
      await _settle();

      expect(controller.segmentIndex, 1);
      expect(media.updates.length, published);
    });

    test('a controller without a media session still plays', () async {
      final plain = TtsController(engine: FakeSpeechEngine());
      addTearDown(plain.dispose);
      await plain.startChapter(_book(), 0);
      expect(plain.status, TtsStatus.playing);
    });
  });
}
