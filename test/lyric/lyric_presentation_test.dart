import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric_presentation.dart';
import 'package:coriander_player/lyric/ttml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presents LRC primary text and combined translation when enabled', () {
    final line = LrcLine(
      Duration.zero,
      'primary┃translated┃continued',
      isBlank: false,
    );

    final presentation = presentLyricLine(line, showTranslation: true);

    expect(presentation.primary, 'primary');
    expect(presentation.translation, 'translated┃continued');
    expect(line.content, 'primary┃translated┃continued');
  });

  test('hides an LRC translation without changing the original line', () {
    final line = LrcLine(
      Duration.zero,
      'primary┃translation',
      isBlank: false,
    );

    final presentation = presentLyricLine(line, showTranslation: false);

    expect(presentation.primary, 'primary');
    expect(presentation.translation, isNull);
    expect(line.content, 'primary┃translation');
  });

  test('presents word-timed lyrics with their translation when enabled', () {
    final line = TtmlLine(
      Duration.zero,
      const Duration(seconds: 1),
      [TtmlWord(Duration.zero, const Duration(seconds: 1), 'primary')],
      'primary',
    )..translation = 'translation';

    final presentation = presentLyricLine(line, showTranslation: true);

    expect(presentation.primary, 'primary');
    expect(presentation.translation, 'translation');
    expect(line.translation, 'translation');
  });

  test('hides a word-timed translation when disabled', () {
    final line = TtmlLine(
      Duration.zero,
      const Duration(seconds: 1),
      [TtmlWord(Duration.zero, const Duration(seconds: 1), 'primary')],
      'primary',
    )..translation = 'translation';

    final presentation = presentLyricLine(line, showTranslation: false);

    expect(presentation.primary, 'primary');
    expect(presentation.translation, isNull);
  });

  test('returns no translation for lines and lyrics without one', () {
    final lrcLine = LrcLine(Duration.zero, 'primary', isBlank: false);
    final syncedLine = TtmlLine(
      Duration.zero,
      const Duration(seconds: 1),
      [TtmlWord(Duration.zero, const Duration(seconds: 1), 'primary')],
      'primary',
    );

    expect(
      presentLyricLine(lrcLine, showTranslation: true).translation,
      isNull,
    );
    expect(
      presentLyricLine(syncedLine, showTranslation: true).translation,
      isNull,
    );
    expect(lyricHasTranslation(Lrc([lrcLine], LrcSource.local)), isFalse);
    expect(lyricHasTranslation(Lrc([syncedLine], LrcSource.local)), isFalse);
  });

  test('detects translations without modifying lyric lines', () {
    final lrcLine = LrcLine(
      Duration.zero,
      'primary┃translation',
      isBlank: false,
    );
    final syncedLine = TtmlLine(
      Duration.zero,
      const Duration(seconds: 1),
      [TtmlWord(Duration.zero, const Duration(seconds: 1), 'primary')],
      'primary',
    )..translation = 'translation';

    expect(lyricHasTranslation(Lrc([lrcLine], LrcSource.local)), isTrue);
    expect(lyricHasTranslation(Lrc([syncedLine], LrcSource.local)), isTrue);
    expect(lrcLine.content, 'primary┃translation');
    expect(syncedLine.translation, 'translation');
  });
}
