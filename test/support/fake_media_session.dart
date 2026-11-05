import 'package:translation_app/services/reader/tts_media_session.dart';

/// Records everything [TtsController] publishes and exposes the callbacks the
/// platform would fire, so lock screen behaviour is testable without plugins.
class FakeMediaSession implements TtsMediaSession {
  final List<TtsMediaInfo> updates = [];
  int clearCalls = 0;
  TtsMediaCommands? commands;

  TtsMediaInfo? get last => updates.isEmpty ? null : updates.last;

  @override
  void bindCommands(TtsMediaCommands commands) {
    this.commands = commands;
  }

  @override
  Future<void> update(TtsMediaInfo info) async {
    updates.add(info);
  }

  @override
  Future<void> clear() async {
    clearCalls++;
  }
}
