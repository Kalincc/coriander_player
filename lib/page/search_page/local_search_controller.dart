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
  final LyricSearchIndex lyricIndex;
  final AudioLibrary library;
  final Future<void> Function() _yieldToEventLoop;

  int _generation = 0;

  LocalSearchController({
    required this.lyricIndex,
    AudioLibrary? library,
    Future<void> Function()? yieldToEventLoop,
  })  : library = library ?? AudioLibrary.instance,
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

    try {
      result.audios.addAll(
        library.audioCollection.where(
          (audio) => audio.title.toLowerCase().contains(queryInLowerCase),
        ),
      );
      if (!await _publishBatch(generation, result)) return;

      result.artists.addAll(
        library.artistCollection.values.where(
          (artist) =>
              artist.name.toLowerCase().contains(artistQueryInLowerCase),
        ),
      );
      if (!await _publishBatch(generation, result)) return;

      result.album.addAll(
        library.albumCollection.values.where(
          (album) => album.name.toLowerCase().contains(queryInLowerCase),
        ),
      );
      if (!await _publishBatch(generation, result)) return;

      result.lyrics.addAll(
        searchLyricEntriesForCompiledQuery(
          query: lyricQuery,
          entries: lyricIndex.entries,
          audios: library.audioCollection,
        ),
      );
      if (!await _publishBatch(generation, result)) return;

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
    UnionSearchResult result,
  ) async {
    await _yieldToEventLoop();
    if (!_isCurrent(generation)) return false;
    value = LocalSearchState(
      result: UnionSearchResult.copyOf(result),
      isLoading: true,
      isComplete: false,
    );
    return true;
  }

  bool _isCurrent(int generation) => generation == _generation;

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
