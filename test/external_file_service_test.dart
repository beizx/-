import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/services/import/external_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ExternalFileService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('takePending decodes the native payload once', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'takePendingFile') return null;
      calls++;
      return calls == 1
          ? {'path': '/cache/external_import/abc-潮汐来信.txt', 'name': '潮汐来信.txt'}
          : null;
    });

    final service = ExternalFileService();
    final first = await service.takePending();
    expect(first, isNotNull);
    expect(first!.name, '潮汐来信.txt');
    expect(first.extension, 'txt');
    expect(first.path, endsWith('潮汐来信.txt'));

    expect(await service.takePending(), isNull);
  });

  test('duplicate pushes of the same path are ignored', () async {
    final received = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      // Simulate the runtime push that follows a cold-start payload.
      return null;
    });

    final service = ExternalFileService();
    service.bind((file) async => received.add(file.name));

    await messenger.handlePlatformMessage(
      ExternalFileService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onFileOpened', {
          'path': '/cache/external_import/abc.txt',
          'name': 'abc.txt',
        }),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      ExternalFileService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onFileOpened', {
          'path': '/cache/external_import/abc.txt',
          'name': 'abc.txt',
        }),
      ),
      (_) {},
    );

    expect(received, ['abc.txt']);
  });

  test('files arriving before bind are queued and then flushed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final service = ExternalFileService();
    await Future<void>.delayed(Duration.zero);

    await messenger.handlePlatformMessage(
      ExternalFileService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onFileOpened', {
          'path': '/cache/external_import/queued.epub',
          'name': 'queued.epub',
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    final received = <String>[];
    service.bind((file) async => received.add(file.extension));
    await service.flushQueue();
    expect(received, ['epub']);
  });

  test('missing plugin degrades to null instead of throwing', () async {
    final service = ExternalFileService();
    expect(await service.takePending(), isNull);
  });

  test('malformed payloads are ignored', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'path': '', 'name': 'x.txt'},
    );
    final service = ExternalFileService();
    expect(await service.takePending(), isNull);
  });
}
