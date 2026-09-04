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

  test('one failed provider does not suppress other candidates', () async {
    final audio = makeAudio('song.flac', 1);

    final results = await uniSearch(audio, providers: [
      FakeProvider(
        ResultSource.qq,
        search: (_, __) => throw StateError('qq unavailable'),
      ),
      FakeProvider(
        ResultSource.netease,
        search: (_, __) async => [
          candidate(ResultSource.netease, '红豆', '王菲', '唱游'),
        ],
      ),
    ]);

    expect(results, hasLength(1));
    expect(results.single.source, ResultSource.netease);
  });

  test('malformed provider rows do not suppress valid candidates', () async {
    final audio = makeAudio('song.flac', 1);

    final results = await uniSearch(audio, providers: [
      FakeProvider(
        ResultSource.kugou,
        search: (_, __) async => [
          candidate(ResultSource.kugou, '', '王菲', '唱游'),
          candidate(ResultSource.kugou, '红豆', '王菲', '唱游'),
        ],
      ),
    ]);

    expect(results, hasLength(1));
    expect(results.single.title, '红豆');
  });
}

class FakeProvider implements OnlineLyricProvider {
  @override
  final ResultSource source;
  final Future<List<SongSearchResult>> Function(String, Audio) _search;
  final Future<OnlineLyricPayload?> Function(SongSearchResult)? _fetch;

  FakeProvider(this.source,
      {required Future<List<SongSearchResult>> Function(String, Audio) search,
      Future<OnlineLyricPayload?> Function(SongSearchResult)? fetch})
      : _search = search,
        _fetch = fetch;

  @override
  Future<List<SongSearchResult>> search(String query, Audio audio) =>
      _search(query, audio);

  @override
  Future<OnlineLyricPayload?> fetch(SongSearchResult candidate) async {
    final fetch = _fetch;
    return fetch == null ? null : fetch(candidate);
  }
}

SongSearchResult candidate(
  ResultSource source,
  String title,
  String artists,
  String album, {
  int? id,
}) =>
    SongSearchResult(
      source,
      title,
      artists,
      album,
      0,
      qqSongId: source == ResultSource.qq ? id : null,
      neteaseSongId: source == ResultSource.netease ? id?.toString() : null,
      kugouSongHash: source == ResultSource.kugou ? id?.toString() : null,
    );

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
