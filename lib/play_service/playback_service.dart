import 'dart:async';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:coriander_player/src/rust/api/smtc_flutter.dart';
import 'package:coriander_player/theme_provider.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

void finalizePlaybackHistorySession(PlaybackHistoryService? historyService) {
  if (historyService == null) return;
  unawaited(historyService.endSession().catchError((err, trace) {
    LOGGER.e('[playback history] $err', stackTrace: trace);
  }));
}

enum PlayMode {
  /// 顺序播放到播放列表结尾
  forward,

  /// 循环整个播放列表
  loop,

  /// 循环播放单曲
  singleLoop;

  static PlayMode? fromString(String playMode) {
    for (var value in PlayMode.values) {
      if (value.name == playMode) return value;
    }
    return null;
  }
}

/// 只通知 now playing 变更
abstract class PlaybackPlaylistController implements Listenable {
  ValueListenable<List<Audio>> get playlist;
  int get playlistIndex;
  void playIndexOfPlaylist(int audioIndex);
}

class PlaybackPlaylistContext {
  List<Audio> _items = [];
  int _currentIndex = 0;

  List<Audio> get items => List.unmodifiable(_items);
  int get currentIndex => _currentIndex;

  void play(int audioIndex, Iterable<Audio> playlist) {
    _items = List<Audio>.from(playlist);
    _currentIndex = audioIndex;
  }
}

class PlaybackService extends ChangeNotifier
    implements PlaybackPlaylistController {
  final PlayService playService;

  late StreamSubscription _playerStateStreamSub;
  late StreamSubscription _smtcEventStreamSub;
  late StreamSubscription _positionStreamSub;

  PlaybackService(this.playService) {
    _playerStateStreamSub = playerStateStream.listen((event) {
      if (event == PlayerState.completed) {
        _endHistorySession();
        _autoNextAudio();
      }
    });

    _smtcEventStreamSub = _smtc.subscribeToControlEvents().listen((event) {
      switch (event) {
        case SMTCControlEvent.play:
          start();
          break;
        case SMTCControlEvent.pause:
          pause();
          break;
        case SMTCControlEvent.previous:
          lastAudio();
          break;
        case SMTCControlEvent.next:
          nextAudio();
          break;
        case SMTCControlEvent.unknown:
      }
    });

    _positionStreamSub = positionStream.listen((progress) {
      _smtc.updateTimeProperties(progress: (progress * 1000).floor());
      if (nowPlaying != null && playerState != PlayerState.unknown) {
        _playbackHistoryService?.recordPosition(
          Duration(milliseconds: (progress * 1000).round()),
        );
      }
    });
  }

  final _player = BassPlayer();
  final _smtc = SmtcFlutter();
  final _pref = AppPreference.instance.playbackPref;

  late final _wasapiExclusive = ValueNotifier(_player.wasapiExclusive);
  ValueNotifier<bool> get wasapiExclusive => _wasapiExclusive;

  /// 独占模式
  void useExclusiveMode(bool exclusive) {
    if (_player.useExclusiveMode(exclusive)) {
      _wasapiExclusive.value = exclusive;
    }
  }

  Audio? nowPlaying;

  PlaybackHistoryService? _playbackHistoryService;
  PlaybackHistoryService? get playbackHistoryService => _playbackHistoryService;

  void attachHistory(PlaybackHistoryService historyService) {
    _playbackHistoryService = historyService;
  }

  void _endHistorySession() {
    finalizePlaybackHistorySession(_playbackHistoryService);
  }

  void _startHistorySession(Audio audio,
      {Duration initialPosition = Duration.zero}) {
    _playbackHistoryService?.startSession(
      audio,
      initialPosition: initialPosition,
    );
  }

  int? _playlistIndex;
  @override
  int get playlistIndex => _playlistIndex ?? 0;

  @override
  final ValueNotifier<List<Audio>> playlist = ValueNotifier([]);
  List<Audio> _playlistBackup = [];
  final playbackContext = PlaybackPlaylistContext();

  void _replacePlaylist(Iterable<Audio> audios, int currentIndex) {
    playbackContext.play(currentIndex, audios);
    playlist.value = playbackContext.items;
    _playlistIndex = currentIndex;
  }

  late final _playMode = ValueNotifier(_pref.playMode);
  ValueNotifier<PlayMode> get playMode => _playMode;

  void setPlayMode(PlayMode playMode) {
    this.playMode.value = playMode;
    _pref.playMode = playMode;
  }

  late final _shuffle = ValueNotifier(false);
  ValueNotifier<bool> get shuffle => _shuffle;

  double get length => _player.length;

  double get position => _player.position;

  PlayerState get playerState => _player.playerState;

  double get volumeDsp => _player.volumeDsp;

  /// 修改解码时的音量（不影响 Windows 系统音量）
  void setVolumeDsp(double volume) {
    _player.setVolumeDsp(volume);
    _pref.volumeDsp = volume;
  }

  Stream<double> get positionStream => _player.positionStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 1. 更新 [_playlistIndex] 为 [audioIndex]
  /// 2. 更新 [nowPlaying] 为 playlist[_nowPlayingIndex]
  /// 3. _bassPlayer.setSource
  /// 4. 设置解码音量
  /// 4. 获取歌词 **将 [_nextLyricLine] 置为0**
  /// 5. 播放
  /// 6. 通知并更新主题色
  Future<void> _loadAndPlay(
    int audioIndex,
    List<Audio> playlist, {
    Duration initialPosition = Duration.zero,
  }) async {
    if (audioIndex < 0 || audioIndex >= playlist.length) return;
    final audio = playlist[audioIndex];
    try {
      _endHistorySession();
      _player.setSource(audio.path);
      _playlistIndex = audioIndex;
      nowPlaying = audio;
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      playService.lyricService.updateLyric();

      _player.start();
      _startHistorySession(audio, initialPosition: initialPosition);
      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

      _smtc.updateState(state: SMTCState.playing);
      _smtc.updateDisplay(
        title: nowPlaying!.title,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.path,
      );

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService
            .sendPlayerStateMessage(playerState == PlayerState.playing);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });
    } catch (err) {
      LOGGER.e("[load and play] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 播放当前播放列表的第几项，只能用在播放列表界面
  @override
  void playIndexOfPlaylist(int audioIndex) {
    unawaited(_loadAndPlay(audioIndex, playlist.value));
  }

  /// 播放playlist[audioIndex]并设置播放列表为playlist
  void play(int audioIndex, List<Audio> playlist) {
    if (shuffle.value) {
      final shuffled = List<Audio>.from(playlist);
      final willPlay = shuffled.removeAt(audioIndex);
      shuffled.shuffle();
      shuffled.insert(0, willPlay);
      _playlistBackup = List.from(playlist);
      _replacePlaylist(shuffled, 0);
      unawaited(_loadAndPlay(0, shuffled));
    } else {
      final queue = List<Audio>.from(playlist);
      _playlistBackup = List.from(playlist);
      _replacePlaylist(queue, audioIndex);
      unawaited(_loadAndPlay(audioIndex, queue));
    }
  }

  void shuffleAndPlay(List<Audio> audios) {
    final shuffled = List<Audio>.from(audios)..shuffle();
    _playlistBackup = List.from(audios);

    shuffle.value = true;

    if (shuffled.isEmpty) return;
    _replacePlaylist(shuffled, 0);
    unawaited(_loadAndPlay(0, shuffled));
  }

  /// 下一首播放
  void addToNext(Audio audio) {
    if (_playlistIndex != null && !playlist.value.contains(audio)) {
      final queue = List<Audio>.from(playlist.value)
        ..insert(_playlistIndex! + 1, audio);
      playlist.value = queue;
      _playlistBackup = List.from(queue);
    }
  }

  void useShuffle(bool flag) {
    if (nowPlaying == null) return;
    if (flag == shuffle.value) return;

    if (flag) {
      _playlistBackup = List<Audio>.from(playlist.value);
      final shuffled = List<Audio>.from(playlist.value)..shuffle();
      shuffled.remove(nowPlaying!);
      shuffled.insert(0, nowPlaying!);
      _replacePlaylist(shuffled, 0);
      _playlistIndex = 0;
      shuffle.value = true;
    } else {
      final original = _playlistBackup.isEmpty
          ? List<Audio>.from(playlist.value)
          : List<Audio>.from(_playlistBackup);
      _replacePlaylist(original, original.indexOf(nowPlaying!));
      _playlistIndex = original.indexOf(nowPlaying!);
      shuffle.value = false;
    }
  }

  void _nextAudio_forward() {
    if (_playlistIndex == null) return;

    if (_playlistIndex! < playlist.value.length - 1) {
      unawaited(_loadAndPlay(_playlistIndex! + 1, playlist.value));
    }
  }

  void _nextAudio_loop() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! + 1;
    if (newIndex >= playlist.value.length) {
      newIndex = 0;
    }

    unawaited(_loadAndPlay(newIndex, playlist.value));
  }

  void _nextAudio_singleLoop() {
    if (_playlistIndex == null) return;

    unawaited(_loadAndPlay(_playlistIndex!, playlist.value));
  }

  void _autoNextAudio() {
    switch (playMode.value) {
      case PlayMode.forward:
        _nextAudio_forward();
        break;
      case PlayMode.loop:
        _nextAudio_loop();
        break;
      case PlayMode.singleLoop:
        _nextAudio_singleLoop();
        break;
    }
  }

  /// 手动下一曲时默认循环播放列表
  void nextAudio() => _nextAudio_loop();

  /// 手动上一曲时默认循环播放列表
  void lastAudio() {
    if (_playlistIndex == null) return;

    int newIndex = _playlistIndex! - 1;
    if (newIndex < 0) {
      newIndex = playlist.value.length - 1;
    }

    unawaited(_loadAndPlay(newIndex, playlist.value));
  }

  /// 暂停
  void pause() {
    try {
      _player.pause();
      _playbackHistoryService?.recordPosition(
        Duration(milliseconds: (_player.position * 1000).round()),
      );
      _endHistorySession();
      _smtc.updateState(state: SMTCState.paused);
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(false);
      });
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复播放
  void start() {
    try {
      if (_player.playerState == PlayerState.unknown &&
          nowPlaying != null &&
          _playlistIndex != null) {
        unawaited(_resumeFromSavedState(Duration.zero));
        return;
      }
      final wasPlaying = _player.playerState == PlayerState.playing;
      _player.start();
      final audio = nowPlaying;
      if (!wasPlaying && audio != null) {
        _startHistorySession(
          audio,
          initialPosition:
              Duration(milliseconds: (_player.position * 1000).round()),
        );
      }
      _smtc.updateState(state: SMTCState.playing);
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(true);
      });
    } catch (err) {
      LOGGER.e("[start]: $err");
      showTextOnSnackBar(err.toString());
    }
  }

  Future<void> _resumeFromSavedState(Duration position) async {
    final index = _playlistIndex;
    if (index == null) return;
    await _loadAndPlay(index, playlist.value, initialPosition: position);
    if (position > Duration.zero && nowPlaying != null) {
      _player.seek(position.inMilliseconds / 1000);
    }
  }

  /// 再次播放。在顺序播放完最后一曲时再次按播放时使用。
  /// 与 [start] 的差别在于它会通知重绘组件
  void playAgain() => _nextAudio_singleLoop();

  void seek(double position) {
    _player.seek(position);
    _playbackHistoryService?.recordSeek(
      Duration(milliseconds: (position * 1000).round()),
    );
    playService.lyricService.findCurrLyricLine();
  }

  void close() {
    _playbackHistoryService?.recordPosition(
      Duration(milliseconds: (_player.position * 1000).round()),
    );
    _endHistorySession();
    _playerStateStreamSub.cancel();
    _smtcEventStreamSub.cancel();
    _positionStreamSub.cancel();
    _player.free();
    _smtc.close();
  }
}
