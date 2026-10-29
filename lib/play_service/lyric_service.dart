import 'dart:async';
import 'dart:math';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/audio_path_key.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';

abstract interface class LyricServiceDelegate {
  Stream<double> get positionStream;
  double get position;
  Audio? get nowPlaying;
  Future<bool> get canSendDesktopLyric;
  void sendDesktopLyricLine(LyricLine line);
}

class _PlayServiceLyricDelegate implements LyricServiceDelegate {
  _PlayServiceLyricDelegate(this.playService);

  final PlayService playService;

  @override
  Future<bool> get canSendDesktopLyric =>
      playService.desktopLyricService.canSendMessage;

  @override
  Audio? get nowPlaying => playService.playbackService.nowPlaying;

  @override
  double get position => playService.playbackService.position;

  @override
  Stream<double> get positionStream =>
      playService.playbackService.positionStream;

  @override
  void sendDesktopLyricLine(LyricLine line) {
    playService.desktopLyricService.sendLyricLineMessage(line);
  }
}

/// 只通知 lyric 变更
class LyricService extends ChangeNotifier {
  LyricService(PlayService playService)
      : this.withDelegate(_PlayServiceLyricDelegate(playService));

  LyricService.withDelegate(this._delegate)
      : _nowPlayingPagePreference = AppPreference.instance.nowPlayingPagePref {
    _positionStreamSubscription =
        _delegate.positionStream.listen(_handlePositionChanged);
    _nowPlayingPagePreference.addListener(_handlePreferenceChanged);
  }

  final LyricServiceDelegate _delegate;
  final NowPlayingPagePreference _nowPlayingPagePreference;
  late final StreamSubscription<double> _positionStreamSubscription;

  Audio? _getNowPlaying() => _delegate.nowPlaying;

  Duration get lyricOffset =>
      Duration(milliseconds: _nowPlayingPagePreference.lyricOffsetMs);

  /// 供 widget 使用
  Future<Lyric?> currLyricFuture = Future.value(null);

  /// 下一行歌词
  int _nextLyricLine = 0;
  int _currentLyricLine = -1;
  int _lyricGeneration = 0;
  bool _disposed = false;

  late final StreamController<int> _lyricLineStreamController =
      StreamController.broadcast(onListen: () {
    _lyricLineStreamController.add(max(_currentLyricLine, 0));
  });

  Stream<int> get lyricLineStream => _lyricLineStreamController.stream;

  /// 重新计算歌词进行到第几行
  void findCurrLyricLine() => refreshCurrentLyric();

  void refreshCurrentLyric() {
    final generation = _lyricGeneration;
    final lyricFuture = currLyricFuture;
    lyricFuture.then((lyric) {
      if (_disposed ||
          generation != _lyricGeneration ||
          lyric == null ||
          lyric.lines.isEmpty) {
        return;
      }

      final audioPosition = _durationFromSeconds(_delegate.position);
      _updateCurrentLyricAt(audioPosition, lyric, forceEmit: true);
    });
  }

  void _handlePositionChanged(double position) {
    final generation = _lyricGeneration;
    final lyricFuture = currLyricFuture;
    lyricFuture.then((lyric) {
      if (_disposed ||
          generation != _lyricGeneration ||
          lyric == null ||
          lyric.lines.isEmpty) {
        return;
      }

      _updateCurrentLyricAt(_durationFromSeconds(position), lyric);
    });
  }

  void _updateCurrentLyricAt(
    Duration audioPosition,
    Lyric lyric, {
    bool forceEmit = false,
  }) {
    final lyricPosition = lyricClockPosition(audioPosition, lyricOffset);
    final next = lyric.lines.indexWhere((line) => line.start > lyricPosition);
    _nextLyricLine = next == -1 ? lyric.lines.length : next;

    final currentLine = max(_nextLyricLine - 1, 0);
    if (!forceEmit && currentLine == _currentLyricLine) return;
    _emitLyricLine(currentLine, lyric);
  }

  void _handlePreferenceChanged() {
    refreshCurrentLyric();
  }

  void _emitLyricLine(int index, Lyric lyric) {
    if (_disposed || index < 0 || index >= lyric.lines.length) return;

    _currentLyricLine = index;
    _lyricLineStreamController.add(index);
    final generation = _lyricGeneration;
    _delegate.canSendDesktopLyric.then((canSend) {
      if (_disposed || generation != _lyricGeneration || !canSend) return;
      _delegate.sendDesktopLyricLine(lyric.lines[index]);
    });
  }

  Future<Lyric?> _getLyricDefault(bool localFirst) async {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return Future.value(null);

    if (localFirst) {
      return (await Lrc.fromAudioPath(nowPlaying)) ??
          (await getMostMatchedLyric(nowPlaying));
    }
    return (await getMostMatchedLyric(nowPlaying)) ??
        (await Lrc.fromAudioPath(nowPlaying));
  }

  /// 根据默认歌词来源获取歌词：
  /// 1. 如果没有指定来源，按照现在的方式寻找歌词（本地优先或在线优先）
  /// 2. 如果指定来源，按照指定的来源获取
  void updateLyric() {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    final lyricSource = lyricSourceForPath(nowPlaying.path);
    final Future<Lyric?> next;
    if (lyricSource == null) {
      next = _getLyricDefault(AppSettings.instance.localLyricFirst);
    } else {
      if (lyricSource.source == LyricSourceType.local) {
        next = Lrc.fromAudioPath(nowPlaying);
      } else {
        next = getOnlineLyric(
          audio: nowPlaying,
          qqSongId: lyricSource.qqSongId,
          kugouSongHash: lyricSource.kugouSongHash,
          neteaseSongId: lyricSource.neteaseSongId,
        );
      }
    }

    _replaceLyric(next);
  }

  void useLocalLyric({Audio? forAudio}) {
    if (!_canApplyTo(forAudio)) return;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;
    _replaceLyric(Lrc.fromAudioPath(nowPlaying));
  }

  void useOnlineLyric() {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    _replaceLyric(getMostMatchedLyric(nowPlaying));
  }

  void useSpecificLyric(Lyric lyric, {Audio? forAudio}) {
    if (!_canApplyTo(forAudio)) return;
    _replaceLyric(Future.value(lyric));
  }

  bool _canApplyTo(Audio? audio) {
    if (_disposed) return false;
    if (audio == null) return true;
    final current = _getNowPlaying();
    return current != null &&
        audioPathKey(current.path) == audioPathKey(audio.path);
  }

  void _replaceLyric(Future<Lyric?> next) {
    final generation = ++_lyricGeneration;
    currLyricFuture.ignore();
    currLyricFuture = next;
    currLyricFuture.then((_) {
      if (_disposed || generation != _lyricGeneration) return;
      refreshCurrentLyric();
    }, onError: (Object _, StackTrace __) {});
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lyricGeneration += 1;
    _nowPlayingPagePreference.removeListener(_handlePreferenceChanged);
    _lyricLineStreamController.close();
    _positionStreamSubscription.cancel();
    super.dispose();
  }
}

Duration _durationFromSeconds(double seconds) => Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
