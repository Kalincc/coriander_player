import 'dart:async';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));
  test('a selection from an old song cannot replace the current lyric',
      () async {
    final delegate = _ImmediateLyricDelegate();
    final service = LyricService.withDelegate(delegate);
    final old = _audio('D:/Music/old.flac');
    delegate.audio = _audio('D:/Music/current.flac');
    service.useSpecificLyric(_lyric('current'));
    final current = service.currLyricFuture;
    service.useSpecificLyric(_lyric('old'), forAudio: old);
    service.useLocalLyric(forAudio: old);
    expect(service.currLyricFuture, same(current));
    service.dispose();
    await delegate.close();
  });

  test('a selection for an equivalent current path is accepted', () async {
    final delegate = _ImmediateLyricDelegate();
    final service = LyricService.withDelegate(delegate);
    delegate.audio = _audio(r'\\?\d:\music\song.flac');
    final selected = _lyric('selected');
    service.useSpecificLyric(selected, forAudio: _audio('D:/Music/Song.flac'));
    expect(await service.currLyricFuture, same(selected));
    service.dispose();
    await delegate.close();
  });

  test('drops a delayed desktop line from an older lyric generation', () async {
    final desktopReady = Completer<bool>();
    final delegate = _DeferredLyricDelegate(desktopReady.future);
    final service = LyricService.withDelegate(delegate);
    final sentLines = <String>[];

    delegate.onLine =
        (line) => sentLines.add((line as UnsyncLyricLine).content);

    try {
      service.useSpecificLyric(_lyric('旧歌曲'));
      await Future<void>.delayed(Duration.zero);

      service.useSpecificLyric(_lyric('当前歌曲'));
      await Future<void>.delayed(Duration.zero);

      desktopReady.complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(sentLines, ['当前歌曲']);
    } finally {
      service.dispose();
      await delegate.close();
    }
  });

  test('drops a delayed old lyric future after a newer lyric is selected',
      () async {
    final delegate = _ImmediateLyricDelegate();
    final service = LyricService.withDelegate(delegate);
    final sentLines = <String>[];
    delegate.onLine =
        (line) => sentLines.add((line as UnsyncLyricLine).content);
    final oldLyric = Completer<Lyric?>();

    try {
      service.currLyricFuture = oldLyric.future;
      service.refreshCurrentLyric();
      service.useSpecificLyric(_lyric('当前歌曲'));
      await Future<void>.delayed(Duration.zero);

      oldLyric.complete(_lyric('旧歌曲'));
      await Future<void>.delayed(Duration.zero);

      expect(sentLines, ['当前歌曲']);
    } finally {
      service.dispose();
      await delegate.close();
    }
  });
}

Audio _audio(String path) =>
    Audio('Song', 'Artist', 'Album', 1, 180, 320, 44100, path, 0, 0, null);

Lrc _lyric(String content) => Lrc(
      [
        LrcLine(
          Duration.zero,
          content,
          isBlank: false,
          length: const Duration(seconds: 1),
        ),
      ],
      LrcSource.local,
    );

class _DeferredLyricDelegate implements LyricServiceDelegate {
  _DeferredLyricDelegate(this._canSendDesktopLyric);

  final Future<bool> _canSendDesktopLyric;
  final _positionController = StreamController<double>.broadcast();
  void Function(LyricLine line)? onLine;

  @override
  Future<bool> get canSendDesktopLyric => _canSendDesktopLyric;

  @override
  Audio? get nowPlaying => audio;
  Audio? audio;

  @override
  double get position => 0;

  @override
  Stream<double> get positionStream => _positionController.stream;

  @override
  void sendDesktopLyricLine(LyricLine line) => onLine?.call(line);

  Future<void> close() => _positionController.close();
}

class _ImmediateLyricDelegate extends _DeferredLyricDelegate {
  _ImmediateLyricDelegate() : super(Future.value(true));
}

class _TestRustLibApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
