import 'dart:async';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

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
  Audio? get nowPlaying => null;

  @override
  double get position => 0;

  @override
  Stream<double> get positionStream => _positionController.stream;

  @override
  void sendDesktopLyricLine(LyricLine line) => onLine?.call(line);

  Future<void> close() => _positionController.close();
}
