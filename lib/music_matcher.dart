import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/krc.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/online_lyric_models.dart';
import 'package:coriander_player/lyric/online_lyric_cache.dart';
import 'package:coriander_player/lyric/qrc.dart';
import 'package:coriander_player/lyric/music_match_normalizer.dart';
import 'package:coriander_player/utils.dart';
import 'package:music_api/music_api.dart';

export 'lyric/online_lyric_models.dart';

Future<List<SongSearchResult>> uniSearch(
  Audio audio, {
  Iterable<OnlineLyricProvider>? providers,
  Duration providerTimeout = const Duration(seconds: 8),
}) async {
  final activeProviders = providers ??
      const <OnlineLyricProvider>[
        _QQOnlineLyricProvider(),
        _KuGouOnlineLyricProvider(),
        _NeteaseOnlineLyricProvider(),
      ];
  final results = await Future.wait(
    activeProviders
        .map((provider) => _searchProvider(provider, audio, providerTimeout)),
  );
  final unique = <String, SongSearchResult>{};
  for (final result in results.expand((rows) => rows)) {
    final key = musicCandidateKey(
      title: result.title,
      artists: result.artists,
      album: result.album,
    );
    final previous = unique[key];
    if (previous == null || result.score > previous.score) unique[key] = result;
  }
  final merged = unique.values.toList()
    ..sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      return scoreOrder != 0
          ? scoreOrder
          : a.source.name.compareTo(b.source.name);
    });
  return merged;
}

Future<List<SongSearchResult>> _searchProvider(
  OnlineLyricProvider provider,
  Audio audio,
  Duration providerTimeout,
) =>
    _searchProviderWithinBudget(provider, audio).timeout(
      providerTimeout,
      onTimeout: () {
        LOGGER.e('${provider.source.name} provider search timed out');
        return const [];
      },
    );

Future<List<SongSearchResult>> _searchProviderWithinBudget(
  OnlineLyricProvider provider,
  Audio audio,
) async {
  final queries = musicSearchQueriesFor(audio);
  if (queries.isEmpty) return const [];
  try {
    final first = await provider.search(queries.first, audio);
    final rows = <SongSearchResult>[...first];
    List<SongSearchResult> titleOnly = const [];
    final hasTitleOnlyQuery =
        audio.artist.trim().isNotEmpty && queries.length > 1;
    if (first.length < 5 && hasTitleOnlyQuery) {
      titleOnly = await provider.search(queries[1], audio);
      rows.addAll(titleOnly);
    }
    final albumQueryIndex = hasTitleOnlyQuery ? 2 : 1;
    if (first.isEmpty &&
        titleOnly.isEmpty &&
        queries.length > albumQueryIndex) {
      rows.addAll(await provider.search(queries[albumQueryIndex], audio));
    }
    return _validRows(rows, provider.source, audio).take(10).toList();
  } catch (err, trace) {
    LOGGER.e('${provider.source.name} provider search failed: $err',
        stackTrace: trace);
    return const [];
  }
}

Iterable<SongSearchResult> _validRows(
  Iterable<SongSearchResult> rows,
  ResultSource source,
  Audio audio,
) sync* {
  for (final row in rows) {
    if (row.source != source ||
        row.title.trim().isEmpty ||
        row.artists.trim().isEmpty ||
        row.album.trim().isEmpty) {
      LOGGER.e('${source.name}: skipped malformed search row');
      continue;
    }
    final score = scoreMusicCandidate(
      audio,
      title: row.title,
      artists: row.artists,
      album: row.album,
      durationSeconds: row.durationSeconds,
    );
    yield SongSearchResult(
      row.source,
      row.title,
      row.artists,
      row.album,
      score.value,
      qqSongId: row.qqSongId,
      neteaseSongId: row.neteaseSongId,
      kugouSongHash: row.kugouSongHash,
      durationSeconds: row.durationSeconds,
      matchReasons: score.reasons.toList(),
    );
  }
}

class _QQOnlineLyricProvider implements OnlineLyricProvider {
  const _QQOnlineLyricProvider();

  @override
  ResultSource get source => ResultSource.qq;

  @override
  Future<List<SongSearchResult>> search(String query, Audio audio) async {
    final answer = await QQ.search(keyWord: query, size: 10);
    final data = _map(answer.data);
    final rows =
        _list(_map(_map(_map(data['req'])['data'])['body'])['item_song']);
    return _mapRows(rows, source, audio, SongSearchResult.fromQQSearchResult);
  }

  @override
  Future<OnlineLyricPayload?> fetch(SongSearchResult candidate) async {
    final id = candidate.qqSongId;
    if (id == null) return null;
    final answer = await QQ.songLyric3(songId: id);
    final data = _map(answer.data);
    final lyric = data['lyric'];
    if (lyric is! String || lyric.isEmpty) return null;
    return OnlineLyricPayload(
      OnlineLyricFormat.qrc,
      lyric,
      data['trans'] is String ? data['trans'] as String : null,
    );
  }
}

class _KuGouOnlineLyricProvider implements OnlineLyricProvider {
  const _KuGouOnlineLyricProvider();

  @override
  ResultSource get source => ResultSource.kugou;

  @override
  Future<List<SongSearchResult>> search(String query, Audio audio) async {
    final answer = await KuGou.searchSong(keyword: query, size: 10);
    final data = _map(answer.data);
    final rows = _list(_map(data['data'])['info']);
    return _mapRows(
        rows, source, audio, SongSearchResult.fromKugouSearchResult);
  }

  @override
  Future<OnlineLyricPayload?> fetch(SongSearchResult candidate) async {
    final hash = candidate.kugouSongHash;
    if (hash == null || hash.isEmpty) return null;
    final answer = await KuGou.krc(hash: hash);
    final lyric = _map(answer.data)['lyric'];
    return lyric is String && lyric.isNotEmpty
        ? OnlineLyricPayload(OnlineLyricFormat.krc, lyric)
        : null;
  }
}

class _NeteaseOnlineLyricProvider implements OnlineLyricProvider {
  const _NeteaseOnlineLyricProvider();

  @override
  ResultSource get source => ResultSource.netease;

  @override
  Future<List<SongSearchResult>> search(String query, Audio audio) async {
    final answer = await Netease.search(keyWord: query, size: 10);
    final data = _map(answer.data);
    final rows = _list(_map(data['result'])['songs']);
    return _mapRows(
        rows, source, audio, SongSearchResult.fromNeteaseSearchResult);
  }

  @override
  Future<OnlineLyricPayload?> fetch(SongSearchResult candidate) async {
    final id = candidate.neteaseSongId;
    if (id == null || id.isEmpty) return null;
    final answer = await Netease.lyric(id: id);
    final data = _map(answer.data);
    final lyric = _map(data['lrc'])['lyric'];
    if (lyric is! String || lyric.isEmpty) return null;
    return OnlineLyricPayload(
      OnlineLyricFormat.lrc,
      lyric,
      _map(data['tlyric'])['lyric'] is String
          ? _map(data['tlyric'])['lyric'] as String
          : null,
    );
  }
}

Map _map(Object? value) => value is Map ? value : const {};

List _list(Object? value) => value is List ? value : const [];

List<SongSearchResult> _mapRows(
  List rows,
  ResultSource source,
  Audio audio,
  SongSearchResult Function(Map, Audio) mapper,
) {
  final results = <SongSearchResult>[];
  for (final row in rows.take(10)) {
    if (row is! Map) {
      LOGGER.e('${source.name}: skipped malformed search row');
      continue;
    }
    try {
      results.add(mapper(row, audio));
    } catch (err, trace) {
      LOGGER.e('${source.name}: skipped malformed search row: $err',
          stackTrace: trace);
    }
  }
  return results;
}

String audioLyricFingerprint(Audio audio) =>
    '${audio.path}|${audio.modified}|${audio.title}|${audio.artist}|${audio.album}';

Lyric? parseOnlineLyricPayload(OnlineLyricPayload payload) {
  if (payload.lyricText.trim().isEmpty) return null;
  try {
    final lyric = switch (payload.format) {
      OnlineLyricFormat.lrc => Lrc.fromLrcText(
          payload.translationText?.trim().isNotEmpty == true
              ? '${payload.lyricText}\n${payload.translationText}'
              : payload.lyricText,
          LrcSource.web,
          separator: '┃',
        ),
      OnlineLyricFormat.krc => Krc.fromKrcText(payload.lyricText),
      OnlineLyricFormat.qrc =>
        Qrc.fromQrcText(payload.lyricText, payload.translationText),
    };
    return lyric != null && lyric.lines.isNotEmpty ? lyric : null;
  } catch (error, trace) {
    LOGGER.e('Could not parse online lyric payload: $error', stackTrace: trace);
    return null;
  }
}

Future<OnlineLyricPayload?> _fetchOnlineLyricPayload(
  ResultSource source,
  String providerId,
) async {
  try {
    switch (source) {
      case ResultSource.qq:
        final answer = await QQ.songLyric3(songId: int.parse(providerId));
        final data = _map(answer.data);
        final lyric = data['lyric'];
        return lyric is String && lyric.isNotEmpty
            ? OnlineLyricPayload(
                OnlineLyricFormat.qrc,
                lyric,
                data['trans'] is String ? data['trans'] as String : null,
              )
            : null;
      case ResultSource.kugou:
        final answer = await KuGou.krc(hash: providerId);
        final lyric = _map(answer.data)['lyric'];
        return lyric is String && lyric.isNotEmpty
            ? OnlineLyricPayload(OnlineLyricFormat.krc, lyric)
            : null;
      case ResultSource.netease:
        final answer = await Netease.lyric(id: providerId);
        final data = _map(answer.data);
        final lyric = _map(data['lrc'])['lyric'];
        return lyric is String && lyric.isNotEmpty
            ? OnlineLyricPayload(
                OnlineLyricFormat.lrc,
                lyric,
                _map(data['tlyric'])['lyric'] is String
                    ? _map(data['tlyric'])['lyric'] as String
                    : null,
              )
            : null;
    }
  } catch (error, trace) {
    LOGGER.e('Could not fetch ${source.name} lyric: $error', stackTrace: trace);
    return null;
  }
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
  Audio? audio,
  OnlineLyricCache? cache,
}) async {
  late final ResultSource source;
  late final String providerId;
  if (qqSongId != null) {
    source = ResultSource.qq;
    providerId = qqSongId.toString();
  } else if (kugouSongHash != null) {
    source = ResultSource.kugou;
    providerId = kugouSongHash;
  } else if (neteaseSongId != null) {
    source = ResultSource.netease;
    providerId = neteaseSongId;
  } else {
    return null;
  }
  final activeCache = cache ?? OnlineLyricCache.defaults();
  final fingerprint = audio == null ? '' : audioLyricFingerprint(audio);
  final key = '${source.name}:$providerId';
  final cached =
      await activeCache.readEntry(key, audioFingerprint: fingerprint);
  if (cached != null) return parseOnlineLyricPayload(cached.payload);

  final payload = await _fetchOnlineLyricPayload(source, providerId);
  if (payload == null) return null;
  final lyric = parseOnlineLyricPayload(payload);
  if (lyric == null) return null;
  try {
    await activeCache.writeEntry(OnlineLyricCacheEntry(
      key: key,
      audioFingerprint: fingerprint,
      payload: payload,
      title: audio?.title ?? '',
      artists: audio?.artist ?? '',
      album: audio?.album ?? '',
      score: 0,
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  } catch (error, trace) {
    LOGGER.e('Could not cache ${source.name} lyric: $error', stackTrace: trace);
  }
  return lyric;
}

Future<Lyric?> getMostMatchedLyric(Audio audio) async {
  final unisearchResult = await uniSearch(audio);
  if (unisearchResult.isEmpty) return null;

  final mostMatch = unisearchResult.first;

  return switch (mostMatch.source) {
    ResultSource.qq => getOnlineLyric(qqSongId: mostMatch.qqSongId),
    ResultSource.kugou =>
      getOnlineLyric(kugouSongHash: mostMatch.kugouSongHash),
    ResultSource.netease =>
      getOnlineLyric(neteaseSongId: mostMatch.neteaseSongId),
  };
}
