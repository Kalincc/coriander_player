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

const _automaticMatchScoreFloor = .62;

Future<List<SongSearchResult>> uniSearch(
  Audio audio, {
  Iterable<OnlineLyricProvider>? providers,
  Duration providerTimeout = const Duration(seconds: 8),
}) async {
  final activeProviders =
      (providers ?? _defaultOnlineLyricProviders).toList(growable: false);
  final outcomes = await Future.wait(
    activeProviders
        .map((provider) => _searchProvider(provider, audio, providerTimeout)),
  );
  return _mergeSearchResults(outcomes.expand((outcome) => outcome.rows));
}

Future<OnlineLyricSearchReport> searchOnlineLyrics(
  Audio audio, {
  Iterable<OnlineLyricProvider>? providers,
  OnlineLyricCache? cache,
  Duration providerTimeout = const Duration(seconds: 8),
}) async {
  final activeProviders =
      (providers ?? _defaultOnlineLyricProviders).toList(growable: false);
  final outcomes = await Future.wait(
    activeProviders
        .map((provider) => _searchProvider(provider, audio, providerTimeout)),
  );
  final liveCandidates =
      _mergeSearchResults(outcomes.expand((outcome) => outcome.rows));
  final cachedCandidates = await _readCachedCandidates(
    audio,
    cache ?? OnlineLyricCache.defaults(),
  );
  return OnlineLyricSearchReport(
    candidates: _mergeCachedCandidates(cachedCandidates, liveCandidates),
    statuses: [
      for (final outcome in outcomes) _statusForOutcome(outcome),
    ],
  );
}

List<SongSearchResult> _mergeSearchResults(
  Iterable<SongSearchResult> results,
) {
  final unique = <String, SongSearchResult>{};
  for (final result in results) {
    final key = '${result.source.name}\u001f${musicCandidateKey(
      title: result.title,
      artists: result.artists,
      album: result.album,
    )}';
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

class _ProviderSearchOutcome {
  final OnlineLyricProvider provider;
  final List<SongSearchResult> rows;
  final String? errorMessage;

  const _ProviderSearchOutcome({
    required this.provider,
    required this.rows,
    this.errorMessage,
  });
}

class _ProviderQueryResult {
  final List<SongSearchResult> rows;
  final String? errorMessage;

  const _ProviderQueryResult({
    required this.rows,
    this.errorMessage,
  });
}

class _ProviderSearchDataError extends FormatException {
  final List<SongSearchResult> rows;

  _ProviderSearchDataError({
    required this.rows,
    required String message,
  }) : super(message);
}

Future<_ProviderSearchOutcome> _searchProvider(
  OnlineLyricProvider provider,
  Audio audio,
  Duration providerTimeout,
) async {
  final queries = musicSearchQueriesFor(audio);
  if (queries.isEmpty) {
    return _ProviderSearchOutcome(provider: provider, rows: const []);
  }
  final stopwatch = Stopwatch()..start();
  String? errorMessage;

  Future<_ProviderQueryResult?> searchBeforeDeadline(String query) async {
    final remaining = providerTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      LOGGER.e('${provider.source.name} provider search timed out');
      errorMessage ??= '请求超时';
      return null;
    }
    try {
      final request = provider.search(query, audio).then<_ProviderQueryResult?>(
          (rows) => _ProviderQueryResult(rows: rows));
      return await request.timeout(
        remaining,
        onTimeout: () {
          LOGGER.e('${provider.source.name} provider search timed out');
          errorMessage ??= '请求超时';
          return null;
        },
      );
    } catch (err, trace) {
      if (err is _ProviderSearchDataError) {
        errorMessage ??= err.message;
        return _ProviderQueryResult(
          rows: err.rows,
          errorMessage: err.message,
        );
      }
      if (err is FormatException) {
        errorMessage ??= _providerErrorMessage(err);
        return _ProviderQueryResult(
          rows: const [],
          errorMessage: errorMessage,
        );
      }
      LOGGER.e('${provider.source.name} provider search failed: $err',
          stackTrace: trace);
      errorMessage ??= _providerErrorMessage(err);
      return null;
    }
  }

  final first = await searchBeforeDeadline(queries.first);
  if (first == null) {
    return _ProviderSearchOutcome(
      provider: provider,
      rows: const [],
      errorMessage: errorMessage ?? '搜索失败',
    );
  }
  final rows = <SongSearchResult>[...first.rows];
  errorMessage ??= first.errorMessage;
  List<SongSearchResult> titleOnly = const [];
  final hasTitleOnlyQuery =
      audio.artist.trim().isNotEmpty && queries.length > 1;
  if (first.rows.length < 5 && hasTitleOnlyQuery) {
    final response = await searchBeforeDeadline(queries[1]);
    if (response == null) {
      return _ProviderSearchOutcome(
        provider: provider,
        rows: _rankProviderRows(rows, provider.source, audio),
        errorMessage: errorMessage,
      );
    }
    errorMessage ??= response.errorMessage;
    titleOnly = response.rows;
    rows.addAll(titleOnly);
  }
  final albumQueryIndex = hasTitleOnlyQuery ? 2 : 1;
  if (first.rows.isEmpty &&
      titleOnly.isEmpty &&
      queries.length > albumQueryIndex) {
    final response = await searchBeforeDeadline(queries[albumQueryIndex]);
    if (response == null) {
      return _ProviderSearchOutcome(
        provider: provider,
        rows: _rankProviderRows(rows, provider.source, audio),
        errorMessage: errorMessage,
      );
    }
    errorMessage ??= response.errorMessage;
    rows.addAll(response.rows);
  }
  return _ProviderSearchOutcome(
    provider: provider,
    rows: _rankProviderRows(rows, provider.source, audio),
    errorMessage: errorMessage,
  );
}

String _providerErrorMessage(Object error) {
  final message = error.toString().trim();
  if (message.isEmpty) return '搜索失败';
  return message.replaceFirst(RegExp(r'^[^:]+:\s*'), '');
}

LyricProviderSearchStatus _statusForOutcome(_ProviderSearchOutcome outcome) {
  final hasResults = outcome.rows.isNotEmpty;
  final hasError = outcome.errorMessage?.trim().isNotEmpty == true;
  final state = switch ((hasResults, hasError)) {
    (true, false) => LyricProviderSearchState.found,
    (true, true) => LyricProviderSearchState.partial,
    (false, true) => LyricProviderSearchState.failed,
    (false, false) => LyricProviderSearchState.noResults,
  };
  return LyricProviderSearchStatus(
    source: outcome.provider.source,
    state: state,
    candidateCount: outcome.rows.length,
    errorMessage: outcome.errorMessage,
  );
}

List<SongSearchResult> _rankProviderRows(
  Iterable<SongSearchResult> rows,
  ResultSource source,
  Audio audio,
) {
  final unique = <String, SongSearchResult>{};
  for (final result in _validRows(rows, source, audio)) {
    final key = musicCandidateKey(
      title: result.title,
      artists: result.artists,
      album: result.album,
    );
    final previous = unique[key];
    if (previous == null || _compareCandidates(result, previous) < 0) {
      unique[key] = result;
    }
  }
  final ranked = unique.values.toList()..sort(_compareCandidates);
  return ranked.take(10).toList();
}

int _compareCandidates(SongSearchResult a, SongSearchResult b) {
  final scoreOrder = b.score.compareTo(a.score);
  if (scoreOrder != 0) return scoreOrder;
  final sourceOrder = a.source.name.compareTo(b.source.name);
  if (sourceOrder != 0) return sourceOrder;
  final titleOrder = a.title.compareTo(b.title);
  if (titleOrder != 0) return titleOrder;
  final artistOrder = a.artists.compareTo(b.artists);
  if (artistOrder != 0) return artistOrder;
  final albumOrder = a.album.compareTo(b.album);
  if (albumOrder != 0) return albumOrder;
  return (_providerIdFor(a) ?? '').compareTo(_providerIdFor(b) ?? '');
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
    final data = _searchMap(answer.data, source, '根响应');
    final req = _searchMap(data['req'], source, 'req');
    final reqData = _searchMap(req['data'], source, 'req.data');
    final body = _searchMap(reqData['body'], source, 'req.data.body');
    final rows = _searchList(body['item_song'], source, 'item_song');
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
    final data = _searchMap(answer.data, source, '根响应');
    final responseData = _searchMap(data['data'], source, 'data');
    final rows = _searchList(responseData['info'], source, 'data.info');
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
    final data = _searchMap(answer.data, source, '根响应');
    final result = _searchMap(data['result'], source, 'result');
    final rows = _searchList(result['songs'], source, 'result.songs');
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

Map _searchMap(Object? value, ResultSource source, String field) {
  if (value is Map) return value;
  throw _ProviderSearchDataError(
    rows: const [],
    message: '${source.name} 搜索响应结构异常：$field',
  );
}

List _searchList(Object? value, ResultSource source, String field) {
  if (value is List) return value;
  throw _ProviderSearchDataError(
    rows: const [],
    message: '${source.name} 搜索响应结构异常：$field',
  );
}

List<SongSearchResult> _mapRows(
  List rows,
  ResultSource source,
  Audio audio,
  SongSearchResult Function(Map, Audio) mapper,
) {
  final results = <SongSearchResult>[];
  var malformedRows = 0;
  for (final row in rows) {
    if (row is! Map) {
      LOGGER.e('${source.name}: skipped malformed search row');
      malformedRows++;
      continue;
    }
    try {
      results.add(mapper(row, audio));
    } catch (err, trace) {
      LOGGER.e('${source.name}: skipped malformed search row: $err',
          stackTrace: trace);
      malformedRows++;
    }
  }
  if (rows.isNotEmpty && results.isEmpty && malformedRows > 0) {
    throw _ProviderSearchDataError(
      rows: results,
      message: '${source.name} 搜索候选格式异常',
    );
  }
  if (malformedRows > 0) {
    throw _ProviderSearchDataError(
      rows: results,
      message: '${source.name} 搜索候选包含格式异常项',
    );
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

Future<List<SongSearchResult>> _readCachedCandidates(
  Audio audio,
  OnlineLyricCache cache,
) async {
  try {
    final entries = await cache.readEntriesForAudioFingerprint(
      audioLyricFingerprint(audio),
    );
    final candidates = <SongSearchResult>[];
    for (final entry in entries) {
      if (parseOnlineLyricPayload(entry.payload) == null) continue;
      final candidate = _cachedCandidate(entry, audio);
      if (candidate != null) candidates.add(candidate);
    }
    return candidates;
  } catch (error, trace) {
    LOGGER.e('Could not read cached lyric candidates: $error',
        stackTrace: trace);
    return const [];
  }
}

SongSearchResult? _cachedCandidate(
  OnlineLyricCacheEntry entry,
  Audio audio,
) {
  final separator = entry.key.indexOf(':');
  if (separator <= 0 || separator == entry.key.length - 1) return null;
  final sourceName = entry.key.substring(0, separator);
  final providerId = entry.key.substring(separator + 1);
  final title = entry.title.trim().isEmpty ? audio.title : entry.title;
  final artists = entry.artists.trim().isEmpty ? audio.artist : entry.artists;
  final album = entry.album.trim().isEmpty ? audio.album : entry.album;
  const cacheReasons = ['缓存命中'];
  final qqSongId = int.tryParse(providerId);
  return switch (sourceName) {
    'qq' when qqSongId == null => null,
    'qq' => SongSearchResult(
        ResultSource.qq,
        title,
        artists,
        album,
        entry.score,
        qqSongId: qqSongId,
        fromCache: true,
        matchReasons: cacheReasons,
      ),
    'kugou' => SongSearchResult(
        ResultSource.kugou,
        title,
        artists,
        album,
        entry.score,
        kugouSongHash: providerId,
        fromCache: true,
        matchReasons: cacheReasons,
      ),
    'netease' => SongSearchResult(
        ResultSource.netease,
        title,
        artists,
        album,
        entry.score,
        neteaseSongId: providerId,
        fromCache: true,
        matchReasons: cacheReasons,
      ),
    _ => null,
  };
}

List<SongSearchResult> _mergeCachedCandidates(
  Iterable<SongSearchResult> cached,
  Iterable<SongSearchResult> live,
) {
  final merged = <SongSearchResult>[];
  final seen = <String>{};
  void add(SongSearchResult candidate) {
    final providerId = _providerIdFor(candidate);
    final key = providerId == null
        ? '${candidate.source.name}\u001f${musicCandidateKey(
            title: candidate.title,
            artists: candidate.artists,
            album: candidate.album,
          )}'
        : '${candidate.source.name}:$providerId';
    if (seen.add(key)) merged.add(candidate);
  }

  for (final candidate in cached) {
    add(candidate);
  }
  for (final candidate in live) {
    add(candidate);
  }
  return merged;
}

Future<Lyric?> getOnlineLyric({
  Audio? audio,
  SongSearchResult? candidate,
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
  Iterable<OnlineLyricProvider>? providers,
  OnlineLyricCache? cache,
  double? minimumCacheScore,
}) async {
  final request = candidate ??
      _candidateForProviderId(
        qqSongId: qqSongId,
        kugouSongHash: kugouSongHash,
        neteaseSongId: neteaseSongId,
      );
  if (request == null) return null;
  final providerId = _providerIdFor(request);
  if (providerId == null) return null;
  final provider = _providerFor(
    request.source,
    providers ?? _defaultOnlineLyricProviders,
  );
  if (provider == null) return null;

  final activeCache = cache ?? OnlineLyricCache.defaults();
  final fingerprint = audio == null ? '' : audioLyricFingerprint(audio);
  final key = '${request.source.name}:$providerId';
  final cached =
      await activeCache.readEntry(key, audioFingerprint: fingerprint);
  if (cached != null &&
      (minimumCacheScore == null || cached.score >= minimumCacheScore)) {
    final lyric = parseOnlineLyricPayload(cached.payload);
    if (lyric != null) return lyric;
    LOGGER.e('Ignoring invalid cached ${request.source.name} lyric');
  } else if (cached != null) {
    LOGGER.e('Ignoring low-score cached ${request.source.name} lyric');
  }

  OnlineLyricPayload? payload;
  try {
    payload = await provider.fetch(request).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        LOGGER.e('${request.source.name} lyric fetch timed out');
        return null;
      },
    );
  } catch (error, trace) {
    LOGGER.e('Could not fetch ${request.source.name} lyric: $error',
        stackTrace: trace);
    return null;
  }
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
      score: request.score,
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  } catch (error, trace) {
    LOGGER.e('Could not cache ${request.source.name} lyric: $error',
        stackTrace: trace);
  }
  return lyric;
}

Future<Lyric?> getMostMatchedLyric(
  Audio audio, {
  Iterable<OnlineLyricProvider>? providers,
  OnlineLyricCache? cache,
}) async {
  final activeProviders =
      (providers ?? _defaultOnlineLyricProviders).toList(growable: false);
  final activeCache = cache ?? OnlineLyricCache.defaults();
  final fingerprint = audioLyricFingerprint(audio);
  try {
    for (final entry
        in await activeCache.readEntriesForAudioFingerprint(fingerprint)) {
      if (entry.score < _automaticMatchScoreFloor) continue;
      final lyric = parseOnlineLyricPayload(entry.payload);
      if (lyric != null && lyric.lines.isNotEmpty) return lyric;
    }
  } catch (error, trace) {
    LOGGER.e('Could not read cached online lyrics: $error', stackTrace: trace);
  }

  final candidates = await uniSearch(audio, providers: activeProviders);
  for (final candidate in candidates.take(8)) {
    if (candidate.score < _automaticMatchScoreFloor) break;
    try {
      final lyric = await getOnlineLyric(
        audio: audio,
        candidate: candidate,
        providers: activeProviders,
        cache: activeCache,
        minimumCacheScore: _automaticMatchScoreFloor,
      );
      if (lyric != null && lyric.lines.isNotEmpty) return lyric;
    } catch (error, trace) {
      LOGGER.e(
          'Could not load ${candidate.source.name} lyric candidate: $error',
          stackTrace: trace);
    }
  }
  return null;
}

const List<OnlineLyricProvider> _defaultOnlineLyricProviders = [
  _QQOnlineLyricProvider(),
  _KuGouOnlineLyricProvider(),
  _NeteaseOnlineLyricProvider(),
];

OnlineLyricProvider? _providerFor(
  ResultSource source,
  Iterable<OnlineLyricProvider> providers,
) {
  for (final provider in providers) {
    if (provider.source == source) return provider;
  }
  return null;
}

SongSearchResult? _candidateForProviderId({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
}) {
  if (qqSongId != null) {
    return SongSearchResult(ResultSource.qq, '', '', '', 0, qqSongId: qqSongId);
  }
  if (kugouSongHash != null && kugouSongHash.isNotEmpty) {
    return SongSearchResult(
      ResultSource.kugou,
      '',
      '',
      '',
      0,
      kugouSongHash: kugouSongHash,
    );
  }
  if (neteaseSongId != null && neteaseSongId.isNotEmpty) {
    return SongSearchResult(
      ResultSource.netease,
      '',
      '',
      '',
      0,
      neteaseSongId: neteaseSongId,
    );
  }
  return null;
}

String? _providerIdFor(SongSearchResult candidate) =>
    switch (candidate.source) {
      ResultSource.qq => candidate.qqSongId?.toString(),
      ResultSource.kugou => candidate.kugouSongHash?.trim().isNotEmpty == true
          ? candidate.kugouSongHash
          : null,
      ResultSource.netease => candidate.neteaseSongId?.trim().isNotEmpty == true
          ? candidate.neteaseSongId
          : null,
    };
