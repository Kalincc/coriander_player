import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clamps lyric offsets to the supported range', () {
    expect(clampLyricOffsetMs(-10001), -10000);
    expect(clampLyricOffsetMs(10001), 10000);
    expect(clampLyricOffsetMs(750), 750);
  });

  test('uses audio position minus offset as the lyric clock', () {
    expect(
      lyricClockPosition(
        const Duration(seconds: 5),
        const Duration(seconds: 1),
      ),
      const Duration(seconds: 4),
    );
    expect(
      lyricClockPosition(
        const Duration(seconds: 5),
        const Duration(seconds: -1),
      ),
      const Duration(seconds: 6),
    );
  });

  test('maps display start to original start plus offset without negatives',
      () {
    expect(
      lyricDisplayStart(
        const Duration(seconds: 4),
        const Duration(seconds: 1),
      ),
      const Duration(seconds: 5),
    );
    expect(
      lyricDisplayStart(
        const Duration(milliseconds: 500),
        const Duration(seconds: -1),
      ),
      Duration.zero,
    );
  });

  test('clamps word progress after applying the lyric offset', () {
    expect(
      lyricWordProgress(
        audioPosition: const Duration(seconds: 5),
        wordStart: const Duration(seconds: 5),
        wordLength: const Duration(seconds: 1),
        offset: const Duration(seconds: 1),
      ),
      0,
    );
    expect(
      lyricWordProgress(
        audioPosition: const Duration(seconds: 7),
        wordStart: const Duration(seconds: 5),
        wordLength: const Duration(seconds: 1),
        offset: const Duration(seconds: 1),
      ),
      1,
    );
    expect(
      lyricWordProgress(
        audioPosition: const Duration(seconds: 20),
        wordStart: const Duration(seconds: 5),
        wordLength: Duration.zero,
        offset: Duration.zero,
      ),
      0,
    );
  });

  test('a positive offset makes a line current one second later', () {
    const lineStart = Duration(seconds: 5);

    expect(
      lyricClockPosition(const Duration(seconds: 5), Duration.zero),
      lineStart,
    );
    expect(
      lyricClockPosition(
        const Duration(seconds: 5),
        const Duration(seconds: 1),
      ),
      const Duration(seconds: 4),
    );
    expect(
      lyricClockPosition(
        const Duration(seconds: 6),
        const Duration(seconds: 1),
      ),
      lineStart,
    );
    expect(
      lyricDisplayStart(lineStart, const Duration(seconds: 1)),
      const Duration(seconds: 6),
    );
  });

  test('indexes original lyric lines with positive negative and reset offsets',
      () {
    final lines = [
      LrcLine(Duration.zero, 'zero', isBlank: false),
      LrcLine(const Duration(seconds: 5), 'five', isBlank: false),
      LrcLine(const Duration(seconds: 10), 'ten', isBlank: false),
    ];
    const audioPosition = Duration(seconds: 6);
    var offset = const Duration(seconds: 2);

    expect(
      lyricLineIndexAt(lines, audioPosition, offset),
      0,
    );

    offset = const Duration(seconds: -5);
    expect(
      lyricLineIndexAt(lines, audioPosition, offset),
      2,
    );

    offset = Duration.zero;
    expect(lyricLineIndexAt(lines, audioPosition, offset), 1);
  });

  test('maps lyric clicks without changing original line starts', () {
    final line = LrcLine(
      const Duration(milliseconds: 500),
      'line',
      isBlank: false,
    );

    expect(
      lyricDisplayStart(line.start, const Duration(seconds: 1)),
      const Duration(milliseconds: 1500),
    );
    expect(
      lyricDisplayStart(line.start, const Duration(seconds: -1)),
      Duration.zero,
    );
    expect(lyricDisplayStart(line.start, Duration.zero), line.start);
    expect(line.start, const Duration(milliseconds: 500));
  });
}
