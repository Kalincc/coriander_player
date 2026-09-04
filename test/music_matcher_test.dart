import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:coriander_player/lyric/music_match_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';

Audio makeAudio(String path, int modified) => Audio(
      '红豆',
      '王菲',
      '唱游',
      1,
      240,
      null,
      null,
      path,
      modified,
      modified,
      'Lofty',
    );

void main() {
  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));
  test('search result scoring uses normalized candidate scoring', () {
    final audio = makeAudio('song.flac', 1);
    final result = SongSearchResult.fromKugouSearchResult({
      'songname': '红豆 (Live)',
      'album_name': '现场',
      'singername': '王菲',
      'hash': 'hash',
    }, audio);

    expect(
        result.score,
        scoreMusicCandidate(
          audio,
          title: '红豆 (Live)',
          artists: '王菲',
          album: '现场',
        ).value);
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
