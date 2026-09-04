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

  test('candidate keys retain version distinctions', () {
    expect(
      musicCandidateKey(title: 'Song', artists: 'Artist', album: 'Album'),
      isNot(musicCandidateKey(
          title: 'Song (Live)', artists: 'Artist', album: 'Album')),
    );
    expect(
      musicCandidateKey(
          title: 'Song (Live)', artists: 'Artist', album: 'Album'),
      isNot(musicCandidateKey(
          title: 'Song Remix', artists: 'Artist', album: 'Album')),
    );
  });

  test('extra version token is a conflict even when one token matches', () {
    final audio = makeAudio('song.flac', 1)
      ..title = 'Song (Live)'
      ..artist = 'Artist'
      ..album = 'Album';

    final score = scoreMusicCandidate(
      audio,
      title: 'Song (Live Remix)',
      artists: 'Artist',
      album: 'Album',
    );

    expect(score.reasons, contains('版本不一致'));
    expect(score.reasons, isNot(contains('版本匹配')));
  });

  test('partial artist overlap uses normalized punctuation and pinyin forms',
      () {
    final audio = makeAudio('song.flac', 1)
      ..title = 'Song'
      ..artist = '王菲、张三'
      ..album = 'Album';

    final score = scoreMusicCandidate(
      audio,
      title: 'Song',
      artists: 'wang fei / 李四',
      album: 'Album',
    );

    expect(score.value, greaterThan(.6));
  });

  test('duration boundaries are two seconds and five seconds', () {
    final audio = makeAudio('song.flac', 1)
      ..title = 'Song'
      ..artist = 'Artist'
      ..album = 'Album';

    final withinTwo = scoreMusicCandidate(audio,
        title: 'Song', artists: 'Artist', album: 'Album', durationSeconds: 12);
    final withinFive = scoreMusicCandidate(audio,
        title: 'Song', artists: 'Artist', album: 'Album', durationSeconds: 15);
    final outside = scoreMusicCandidate(audio,
        title: 'Song', artists: 'Artist', album: 'Album', durationSeconds: 16);

    expect(withinTwo.value, closeTo(1.0, 1e-9));
    expect(withinFive.value, closeTo(.95, 1e-9));
    expect(outside.value, closeTo(.9, 1e-9));
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
