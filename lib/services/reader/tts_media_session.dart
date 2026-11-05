import 'package:flutter/foundation.dart';

/// What the operating system's media UI (lock screen, notification, headset
/// buttons, CarPlay / Android Auto) needs to describe one listening session.
@immutable
class TtsMediaInfo {
  const TtsMediaInfo({
    required this.bookTitle,
    required this.chapterTitle,
    required this.isPlaying,
    required this.canSkipPrevious,
    required this.canSkipNext,
  });

  final String bookTitle;
  final String chapterTitle;
  final bool isPlaying;
  final bool canSkipPrevious;
  final bool canSkipNext;

  @override
  bool operator ==(Object other) =>
      other is TtsMediaInfo &&
      other.bookTitle == bookTitle &&
      other.chapterTitle == chapterTitle &&
      other.isPlaying == isPlaying &&
      other.canSkipPrevious == canSkipPrevious &&
      other.canSkipNext == canSkipNext;

  @override
  int get hashCode => Object.hash(
    bookTitle,
    chapterTitle,
    isPlaying,
    canSkipPrevious,
    canSkipNext,
  );
}

/// Commands the media UI sends back to the app.
class TtsMediaCommands {
  const TtsMediaCommands({
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onNext,
    required this.onPrevious,
  });

  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onStop;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
}

/// Seam over the platform media session.
///
/// [TtsController] only depends on this interface: the plugin lives in
/// `audio_service_media_session.dart`, so unit tests (and desktop builds) can
/// run without any platform channel.
abstract interface class TtsMediaSession {
  /// Registers the callbacks fired by lock screen / headset buttons.
  void bindCommands(TtsMediaCommands commands);

  /// Publishes the current session to the OS. Safe to call often.
  Future<void> update(TtsMediaInfo info);

  /// Removes the notification / now-playing entry.
  Future<void> clear();
}
