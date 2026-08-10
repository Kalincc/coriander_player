import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:flutter_test/flutter_test.dart';

NowPlayingPagePreference newPreference() => NowPlayingPagePreference(
      NowPlayingViewMode.withLyric,
      LyricTextAlign.left,
      22.0,
      18.0,
    );

void main() {
  test('uses default lyric display preferences', () {
    final preference = newPreference();

    expect(preference.lyricOffsetMs, 0);
    expect(preference.showTranslation, isTrue);
  });

  test('round trips lyric display preferences through a map', () {
    final preference = newPreference()
      ..setLyricOffsetMs(-650)
      ..setShowTranslation(false);

    final restored = NowPlayingPagePreference.fromMap(preference.toMap());

    expect(restored.lyricOffsetMs, -650);
    expect(restored.showTranslation, isFalse);
  });

  test('uses defaults for missing or malformed lyric display preferences', () {
    final oldPreference = NowPlayingPagePreference.fromMap({
      'nowPlayingViewMode': 'withLyric',
      'lyricTextAlign': 'left',
      'lyricFontSize': 22.0,
      'translationFontSize': 18.0,
    });
    final malformedPreference = NowPlayingPagePreference.fromMap({
      'nowPlayingViewMode': 'withLyric',
      'lyricTextAlign': 'left',
      'lyricFontSize': 22.0,
      'translationFontSize': 18.0,
      'lyricOffsetMs': 'not a number',
      'showTranslation': 'not a bool',
    });

    expect(oldPreference.lyricOffsetMs, 0);
    expect(oldPreference.showTranslation, isTrue);
    expect(malformedPreference.lyricOffsetMs, 0);
    expect(malformedPreference.showTranslation, isTrue);
  });

  test('accepts numeric offsets from JSON maps', () {
    final preference = NowPlayingPagePreference.fromMap({
      'nowPlayingViewMode': 'withLyric',
      'lyricTextAlign': 'left',
      'lyricFontSize': 22.0,
      'translationFontSize': 18.0,
      'lyricOffsetMs': 1250.9,
      'showTranslation': false,
    });

    expect(preference.lyricOffsetMs, 1250);
    expect(preference.showTranslation, isFalse);
  });

  test('clamps a changed offset and notifies once', () {
    final preference = newPreference();
    var notificationCount = 0;
    preference.addListener(() => notificationCount++);

    preference.setLyricOffsetMs(20000);
    preference.setLyricOffsetMs(10000);

    expect(preference.lyricOffsetMs, 10000);
    expect(notificationCount, 1);
  });

  test('notifies when the translation visibility changes', () {
    final preference = newPreference();
    var notificationCount = 0;
    preference.addListener(() => notificationCount++);

    preference.setShowTranslation(false);
    preference.setShowTranslation(false);

    expect(preference.showTranslation, isFalse);
    expect(notificationCount, 1);
  });
}
