import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../core/app_info.dart';
import 'tts_media_session.dart';

/// Boots the platform media session used by 听书.
///
/// * Android: `audio_service` runs a media-playback foreground service, which
///   is what keeps the TTS engine alive with the screen off and shows the
///   MediaSession notification.
/// * iOS: the same handler feeds `MPNowPlayingInfoCenter` and
///   `MPRemoteCommandCenter`; together with the `audio` background mode and an
///   `AVAudioSession` playback category configured here, speech keeps playing
///   when the app is backgrounded or the screen is locked.
///
/// Returns `null` when the platform has no media session (desktop, tests) or
/// when the plugin fails, so 听书 still works through the in-app player.
Future<TtsMediaSession?> initTtsMediaSession() async {
  try {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.speech());

    final handler = await AudioService.init(
      builder: AudioServiceMediaSession.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yiyue.translation_app.channel.tts',
        androidNotificationChannelName: '听书播放',
        androidNotificationChannelDescription: '锁屏与通知栏的朗读控制',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        androidNotificationClickStartsActivity: true,
        androidShowNotificationBadge: false,
      ),
    );
    handler.bindAudioSession(audioSession);
    return handler;
  } on Object catch (error) {
    debugPrint('听书媒体会话不可用：$error');
    return null;
  }
}

/// [TtsMediaSession] backed by `audio_service`.
///
/// The handler owns no playback state of its own: [TtsController] pushes a
/// [TtsMediaInfo] snapshot after every change and receives the lock screen
/// buttons back through [TtsMediaCommands].
class AudioServiceMediaSession extends BaseAudioHandler
    implements TtsMediaSession {
  TtsMediaCommands? _commands;
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;
  String? _mediaId;
  bool _audioActive = false;
  bool _playingBeforeInterruption = false;

  /// Hooks the platform audio session so phone calls and unplugged headphones
  /// pause playback instead of shouting into the room.
  void bindAudioSession(AudioSession session) {
    _audioSession = session;
    _interruptionSubscription?.cancel();
    _noisySubscription?.cancel();
    _interruptionSubscription = session.interruptionEventStream.listen(
      _handleInterruption,
    );
    _noisySubscription = session.becomingNoisyEventStream.listen((_) {
      unawaited(_commands?.onPause() ?? Future<void>.value());
    });
  }

  @override
  void bindCommands(TtsMediaCommands commands) {
    _commands = commands;
  }

  @override
  Future<void> update(TtsMediaInfo info) async {
    final mediaId = '${info.bookTitle}\u0000${info.chapterTitle}';
    if (mediaId != _mediaId) {
      _mediaId = mediaId;
      mediaItem.add(
        MediaItem(
          id: mediaId,
          title: info.chapterTitle,
          album: info.bookTitle,
          artist: AppInfo.name,
          displayTitle: info.chapterTitle,
          displaySubtitle: info.bookTitle,
          displayDescription: AppInfo.name,
        ),
      );
    }

    final controls = <MediaControl>[
      if (info.canSkipPrevious) MediaControl.skipToPrevious,
      if (info.isPlaying) MediaControl.pause else MediaControl.play,
      if (info.canSkipNext) MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {MediaAction.stop},
        androidCompactActionIndices: [
          for (var index = 0; index < controls.length; index++) index,
        ],
        processingState: AudioProcessingState.ready,
        playing: info.isPlaying,
      ),
    );
    await _setAudioSessionActive(info.isPlaying);
  }

  @override
  Future<void> clear() async {
    _mediaId = null;
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await _setAudioSessionActive(false);
  }

  @override
  Future<void> play() async {
    await _setAudioSessionActive(true);
    await _commands?.onPlay();
  }

  @override
  Future<void> pause() async {
    await _commands?.onPause();
  }

  @override
  Future<void> stop() async {
    await _commands?.onStop();
    await clear();
  }

  @override
  Future<void> skipToNext() async {
    await _commands?.onNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _commands?.onPrevious();
  }

  Future<void> _setAudioSessionActive(bool active) async {
    final session = _audioSession;
    if (session == null || active == _audioActive) return;
    _audioActive = active;
    try {
      await session.setActive(active);
    } on Object catch (error) {
      debugPrint('音频会话激活失败：$error');
    }
  }

  void _handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      // Remember whether we were speaking so a phone call that ends does not
      // start playback the user had already paused themselves.
      _playingBeforeInterruption = playbackState.value.playing;
      unawaited(_commands?.onPause() ?? Future<void>.value());
      return;
    }
    final shouldResume =
        _playingBeforeInterruption &&
        event.type == AudioInterruptionType.pause;
    _playingBeforeInterruption = false;
    if (shouldResume) {
      unawaited(_commands?.onPlay() ?? Future<void>.value());
    }
  }
}
