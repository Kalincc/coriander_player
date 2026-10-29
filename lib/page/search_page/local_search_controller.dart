import 'dart:async';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/artist_name_normalizer.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/library/lyric_search_normalizer.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:flutter/foundation.dart';

@immutable
class LocalSearchState {
  final UnionSearchResult result;
  final bool isLoading;
  final bool isComplete;
  final Object? error;

  const LocalSearchState({
    required this.result,
    required this.isLoading,
    required this.isComplete,
    this.error,
  });
}

class LocalSearchController extends ValueNotifier<LocalSearchState> {
  static const _searchBatchSize = 25;

  final LyricSearchIndex lyricIndex;
  final AudioLibrary Function() _libraryProvider;
  final Future<void> Function() _yieldToEventLoop;

  int _generation = 0;
  final _publicationClock = Stopwatch()..start();
  int _lastPublishedMicros = 0;

  LocalSearchController({
    required this.lyricIndex,
    AudioLibrary Function()? libraryProvider,
    Future<void> Function()? yieldToEventLoop,
  })  : _libraryProvider = libraryProvider ?? (() => AudioLibrary.instance),
        _yieldToEventLoop =
            yieldToEventLoop ?? (() => Future<void>.delayed(Duration.zero)),
        super(
          LocalSearchState(
            result: UnionSearchResult(''),
            isLoading: false,
            isComplete: true,
          ),
        );

  Future<void> search(String query) async {
    final generation = ++_generation;
    final library = _libraryProvider();
    final normalizedQuery = query.trim();
    final result = UnionSearchResult(normalizedQuery);
    value = LocalSearchState(
      result: UnionSearchResult.copyOf(result),
      isLoading: true,
      isComplete: false,
    );

    if (normalizedQuery.isEmpty) {
      if (_isCurrent(generation)) {
        value = LocalSearchState(
          result: UnionSearchResult.copyOf(result),
          isLoading: false,
          isComplete: true,
        );
      }
      return;
    }

    final queryInLowerCase = normalizedQuery.toLowerCase();
    final artistQueryInLowerCase =
        normalizeArtistName(normalizedQuery).toLowerCase();
    final lyricQuery = CompiledLyricQuery.compile(normalizedQuery);
    final audios = List<Audio>.of(library.audioCollection);

    try {
      if (!await _searchMetadataBatches<Audio>(
        generation: generation,
        result: result,
        items: audios,
        matches: (audio) =>
            audio.title.toLowerCase().contains(queryInLowerCase),
        found: result.audios,
      )) {
        return;
      }

      if (!await _searchMetadataBatches<Artist>(
        generation: generation,
        result: result,
        items: library.artistCollection.values.toList(growable: false),
        matches: (artist) =>
            artist.name.toLowerCase().contains(artistQueryInLowerCase),
        found: result.artists,
      )) {
        return;
      }

      if (!await _searchMetadataBatches<Album>(
        generation: generation,
        result: result,
        items: library.albumCollection.values.toList(growable: false),
        matches: (album) => album.name.toLowerCase().contains(queryInLowerCase),
        found: result.album,
      )) {
        return;
      }

      if (!await _searchLyricBatches(
        generation: generation,
        result: result,
        audios: audios,
        query: lyricQuery,
      )) {
        return;
      }

      if (_isCurrent(generation)) {
        value = LocalSearchState(
          result: UnionSearchResult.copyOf(result),
          isLoading: false,
          isComplete: true,
        );
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        value = LocalSearchState(
          result: UnionSearchResult.copyOf(result),
          isLoading: false,
          isComplete: true,
          error: error,
        );
      }
    }
  }

  Future<bool> _publishBatch(
    int generation,
    UnionSearchResult result, {
    bool force = false,
  }) async {
    await _yieldToEventLoop();
    if (!_isCurrent(generation)) return false;
    // Keep yielding every batch, but only copy cumulative results once per frame
    // (plus category boundaries). Otherwise a broad query copies O(n²) items.
    // ponytail: snapshots still copy hits; use persistent chunks only if profiling
    // shows copying remains a bottleneck after limiting publication frequency.
    final now = _publicationClock.elapsedMicroseconds;
    if (!force && now - _lastPublishedMicros < 16000) return true;
    _lastPublishedMicros = now;
    value = LocalSearchState(
      result: UnionSearchResult.copyOf(result),
      isLoading: true,
      isComplete: false,
    );
    return true;
  }

  Future<bool> _searchMetadataBatches<T>({
    required int generation,
    required UnionSearchResult result,
    required List<T> items,
    required bool Function(T) matches,
    required List<T> found,
  }) async {
    if (items.isEmpty) return _publishBatch(generation, result, force: true);
    for (var start = 0; start < items.length; start += _searchBatchSize) {
      if (!_isCurrent(generation)) return false;
      final end = (start + _searchBatchSize).clamp(0, items.length);
      found.addAll(items.getRange(start, end).where(matches));
      if (!await _publishBatch(generation, result,
          force: start == 0 || end == items.length)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _searchLyricBatches({
    required int generation,
    required UnionSearchResult result,
    required List<Audio> audios,
    required CompiledLyricQuery query,
  }) async {
    if (lyricIndex.entries.isEmpty) {
      return _publishBatch(generation, result, force: true);
    }
    for (var start = 0; start < audios.length; start += _searchBatchSize) {
      if (!_isCurrent(generation)) return false;
      final end = (start + _searchBatchSize).clamp(0, audios.length);
      for (final audio in audios.getRange(start, end)) {
        final match = searchLyricEntryForCompiledQuery(
          query: query,
          entry: lyricIndex.entries[audio.path],
          audio: audio,
        );
        if (match != null) result.lyrics.add(match);
      }
      if (!await _publishBatch(generation, result,
          force: start == 0 || end == audios.length)) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrent(int generation) => generation == _generation;

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
