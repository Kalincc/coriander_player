import 'package:coriander_player/lyric/lyric_timing.dart';
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
}
