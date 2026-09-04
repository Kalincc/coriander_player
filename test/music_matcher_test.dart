import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/online_lyric_cache.dart';
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

  test('provider fallback work shares one timeout budget', () async {
    final audio = makeAudio('song.flac', 1);
    final slowQueries = <String>[];
    final watch = Stopwatch()..start();

    final results = await uniSearch(
      audio,
      providerTimeout: const Duration(milliseconds: 60),
      providers: [
        FakeProvider(
          ResultSource.qq,
          search: (query, _) async {
            slowQueries.add(query);
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return const [];
          },
        ),
        FakeProvider(
          ResultSource.netease,
          search: (_, __) async => [
            candidate(ResultSource.netease, '红豆', '王菲', '唱游'),
          ],
        ),
      ],
    );
    watch.stop();

    expect(results, hasLength(1));
    expect(results.single.source, ResultSource.netease);
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 110)));
    expect(slowQueries, hasLength(2));
  });

  test('missing artist does not issue album fallback after title results',
      () async {
    final audio = Audio(
      '红豆',
      '',
      '唱游',
      1,
      240,
      null,
      null,
      'song.flac',
      1,
      1,
      'Lofty',
    );
    final queries = <String>[];

    await uniSearch(audio, providers: [
      FakeProvider(
        ResultSource.qq,
        search: (query, _) async {
          queries.add(query);
          return [candidate(ResultSource.qq, '红豆', '王菲', '唱游', id: 1)];
        },
      ),
    ]);

    expect(queries, ['红豆']);
  });

  test('online lyric loads a matching cached payload before any provider call',
      () async {
    String? contents;
    final cache = OnlineLyricCache(
      read: () async => contents,
      write: (value) async => contents = value,
    );
    final audio = makeAudio('song.flac', 1);
    await cache.writeEntry(OnlineLyricCacheEntry(
      key: 'qq:1',
      audioFingerprint: audioLyricFingerprint(audio),
      payload: const OnlineLyricPayload(
        OnlineLyricFormat.lrc,
        '[00:01.00]cached primary',
        '[00:01.00]cached translation',
      ),
      title: audio.title,
      artists: audio.artist,
      album: audio.album,
      score: 1,
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));

    final lyric = await HttpOverrides.runZoned(
      () => getOnlineLyric(
        qqSongId: 1,
        audio: audio,
        cache: cache,
      ),
      createHttpClient: (_) => throw StateError('provider fetch was attempted'),
    );

    expect(lyric, isNotNull);
    expect(lyric!.lines, hasLength(1));
    expect((lyric.lines.single as dynamic).content,
        'cached primary┃cached translation');
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
