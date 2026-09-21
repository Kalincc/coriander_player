import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_presentation.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/play_service/desktop_lyric_message_queue.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:desktop_lyric/message.dart' as msg;

msg.LyricLineChangedMessage? desktopLyricLineMessage(
  LyricLine line, {
  required bool showTranslation,
}) {
  final length = switch (line) {
    SyncLyricLine() => line.length,
    LrcLine() => line.length,
    _ => null,
  };
  if (length == null) return null;

  final presentation = presentLyricLine(
    line,
    showTranslation: showTranslation,
  );
  return msg.LyricLineChangedMessage(
    presentation.primary,
    length,
    presentation.translation,
  );
}

class DesktopLyricService extends ChangeNotifier {
  final PlayService playService;
  DesktopLyricService(this.playService) {
    _resetMessageQueue();
  }

  PlaybackService get _playbackService => playService.playbackService;

  Future<Process?> desktopLyric = Future.value(null);
  StreamSubscription? _desktopLyricSubscription;
  late DesktopLyricMessageQueue _messageQueue;
  int _processGeneration = 0;

  bool isLocked = false;

  void _resetMessageQueue() {
    final generation = _processGeneration;
    _messageQueue = DesktopLyricMessageQueue(
      (frame) => _writeFrame(generation, frame),
      onRecovery: () => _writeCurrentPlaybackState(generation),
    );
  }

  Future<bool> _writeCurrentPlaybackState(int generation) async {
    final playbackState = _playbackService.playerState;
    final isPlaying = playbackState == PlayerState.playing;
    final nowPlaying = _playbackService.nowPlaying;
    final title = nowPlaying?.title;
    final artist = nowPlaying?.artist;
    final album = nowPlaying?.album;

    await _writeFrame(
      generation,
      '${msg.PlayerStateChangedMessage(isPlaying).buildMessageJson()}\n',
    );

    if (nowPlaying != null) {
      await _writeFrame(
        generation,
        '${msg.NowPlayingChangedMessage(
          nowPlaying.title,
          nowPlaying.artist,
          nowPlaying.album,
        ).buildMessageJson()}\n',
      );
    }

    final current = _playbackService.nowPlaying;
    return _playbackService.playerState == playbackState &&
        current?.path == nowPlaying?.path &&
        current?.title == title &&
        current?.artist == artist &&
        current?.album == album;
  }

  Future<void> _writeFrame(int generation, String frame) async {
    if (generation != _processGeneration) return;

    final process = await desktopLyric;
    if (generation != _processGeneration) return;

    final stdin = process?.stdin;
    if (stdin == null) return;
    stdin.write(frame);
    await stdin.flush();
  }

  Future<void> startDesktopLyric() async {
    _processGeneration += 1;
    _resetMessageQueue();

    final desktopLyricPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "desktop_lyric",
      'desktop_lyric.exe',
    );

    final nowPlaying = _playbackService.nowPlaying;
    final currScheme = ThemeProvider.instance.currScheme;
    final isDarkMode = ThemeProvider.instance.themeMode == ThemeMode.dark;
    desktopLyric = Process.start(desktopLyricPath, [
      json.encode(msg.InitArgsMessage(
        _playbackService.playerState == PlayerState.playing,
        nowPlaying?.title ?? "无",
        nowPlaying?.artist ?? "无",
        nowPlaying?.album ?? "无",
        isDarkMode,
        currScheme.primary.value,
        currScheme.surfaceContainer.value,
        currScheme.onSurface.value,
      ).toJson())
    ]);

    final process = await desktopLyric;

    process?.stderr.transform(utf8.decoder).listen((event) {
      LOGGER.e("[desktop lyric] $event");
    });

    _desktopLyricSubscription = process?.stdout.transform(utf8.decoder).listen(
      (event) {
        try {
          final Map messageMap = json.decode(event);
          final String messageType = messageMap["type"];
          final messageContent = messageMap["message"] as Map<String, dynamic>;
          if (messageType ==
              msg.getMessageTypeName<msg.ControlEventMessage>()) {
            final controlEvent =
                msg.ControlEventMessage.fromJson(messageContent);
            switch (controlEvent.event) {
              case msg.ControlEvent.pause:
                _playbackService.pause();
                break;
              case msg.ControlEvent.start:
                _playbackService.start();
                break;
              case msg.ControlEvent.previousAudio:
                _playbackService.lastAudio();
                break;
              case msg.ControlEvent.nextAudio:
                _playbackService.nextAudio();
                break;
              case msg.ControlEvent.lock:
                isLocked = true;
                notifyListeners();
                break;
              case msg.ControlEvent.close:
                killDesktopLyric();
                break;
            }
          }
        } catch (err) {
          LOGGER.e("[desktop lyric] $err");
        }
      },
    );

    notifyListeners();
  }

  Future<bool> get canSendMessage => desktopLyric.then(
        (value) => value != null,
      );

  void sendMessage(
    msg.Message message, {
    DesktopLyricFrameGuard? isFrameCurrent,
  }) {
    _messageQueue
        .enqueue(message, isFrameCurrent: isFrameCurrent)
        .catchError((err, trace) {
      LOGGER.e(err, stackTrace: trace);
    });
  }

  void killDesktopLyric() {
    final process = desktopLyric;
    _processGeneration += 1;
    desktopLyric = Future.value(null);
    _resetMessageQueue();

    process.then((value) {
      value?.kill();

      _desktopLyricSubscription?.cancel();
      _desktopLyricSubscription = null;

      notifyListeners();
    }).catchError((err, trace) {
      LOGGER.e(err, stackTrace: trace);
    });
  }

  void sendUnlockMessage() {
    sendMessage(const msg.UnlockMessage());
    isLocked = false;
    notifyListeners();
  }

  void sendThemeModeMessage(bool darkMode) {
    sendMessage(msg.ThemeModeChangedMessage(darkMode));
  }

  void sendThemeMessage(ColorScheme scheme) {
    sendMessage(msg.ThemeChangedMessage(
      scheme.primary.value,
      scheme.surfaceContainer.value,
      scheme.onSurface.value,
    ));
  }

  void sendPlayerStateMessage(bool isPlaying) {
    sendMessage(msg.PlayerStateChangedMessage(isPlaying));
  }

  void sendNowPlayingMessage(Audio nowPlaying) {
    sendMessage(
      msg.NowPlayingChangedMessage(
        nowPlaying.title,
        nowPlaying.artist,
        nowPlaying.album,
      ),
      isFrameCurrent: () {
        final current = _playbackService.nowPlaying;
        return current?.path == nowPlaying.path &&
            current?.title == nowPlaying.title &&
            current?.artist == nowPlaying.artist &&
            current?.album == nowPlaying.album;
      },
    );
  }

  void sendLyricLineMessage(LyricLine line) {
    final message = desktopLyricLineMessage(
      line,
      showTranslation:
          AppPreference.instance.nowPlayingPagePref.showTranslation,
    );
    if (message != null) {
      final audioPath = _playbackService.nowPlaying?.path;
      sendMessage(
        message,
        isFrameCurrent: () =>
            audioPath != null && _playbackService.nowPlaying?.path == audioPath,
      );
    }
  }
}
