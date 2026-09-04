import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/music_match_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';

Audio makeAudio(String path, int modified) => Audio(
      path,
      'Artist',
      'Album',
      1,
      10,
      null,
      null,
      path,
      modified,
      modified,
      'Lofty',
    );

void main() {
  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));
  test('builds bounded queries from title, artist and album', () {
    final audio = makeAudio('song.flac', 1)
      ..title = '01 红豆 (Live) feat. 王菲'
      ..artist = '王菲'
      ..album = '唱游';

    expect(musicSearchQueriesFor(audio), [
      '红豆 王菲',
      '红豆',
      '红豆 唱游',
    ]);
  });

  test('exact title and artist outrank a version conflict', () {
    final audio = makeAudio('song.flac', 1)
      ..title = '红豆'
      ..artist = '王菲'
      ..album = '唱游';

    final exact = scoreMusicCandidate(
      audio,
      title: '红豆',
      artists: '王菲',
      album: '唱游',
      durationSeconds: 240,
    );
    final live = scoreMusicCandidate(
      audio,
      title: '红豆 (Live)',
      artists: '王菲',
      album: '现场',
      durationSeconds: 310,
    );

    expect(exact.value, greaterThan(live.value));
    expect(live.reasons, contains('版本不一致'));
  });
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
