import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/krc.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/online_lyric_models.dart';
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

Future<Lrc?> _getNeteaseUnsyncLyric(String neteaseSongId) async {
  try {
    final answer = await Netease.lyric(id: neteaseSongId);
    final lrcText = answer.data["lrc"]["lyric"];
    if (lrcText is String) {
      final lrcTrans = answer.data["tlyric"]["lyric"];
      return Lrc.fromLrcText(
        lrcText + lrcTrans,
        LrcSource.web,
        separator: "┃",
      );
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Qrc?> _getQQSyncLyric(int qqSongId) async {
  try {
    final answer = await QQ.songLyric3(songId: qqSongId);
    final qrcText = answer.data["lyric"];
    if (qrcText is String) {
      final qrcTransRawStr = answer.data["trans"];
      if (qrcTransRawStr is String) {
        return Qrc.fromQrcText(qrcText, qrcTransRawStr);
      }
      return Qrc.fromQrcText(qrcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Krc?> _getKugouSyncLyric(String kugouSongHash) async {
  try {
    final answer = await KuGou.krc(hash: kugouSongHash);
    final krcText = answer.data["lyric"];
    if (krcText is String) {
      return Krc.fromKrcText(krcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
}) async {
  Lyric? lyric;
  if (qqSongId != null) {
    lyric = (await _getQQSyncLyric(qqSongId));
  } else if (kugouSongHash != null) {
    lyric = (await _getKugouSyncLyric(kugouSongHash));
  } else if (neteaseSongId != null) {
    lyric = await _getNeteaseUnsyncLyric(neteaseSongId);
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
