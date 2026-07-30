import 'dart:convert';
import 'dart:math';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:flutter/foundation.dart';

typedef ReadLyricIndex = Future<String?> Function();
typedef WriteLyricIndex = Future<void> Function(String contents);
typedef ReadLyricFingerprint = Future<LyricFileFingerprint> Function(
  Audio audio,
);
typedef ReadLocalLyricLines = Future<List<LyricSearchLine>> Function(
  Audio audio,
);

@immutable
class LyricIndexProgress {
  final int processed;
  final int total;
  final bool isSyncing;
  final Object? error;

  const LyricIndexProgress({
    this.processed = 0,
    this.total = 0,
    this.isSyncing = false,
    this.error,
  });
}

class LyricSearchIndex extends ChangeNotifier {
  static const int formatVersion = 1;

  final ReadLyricIndex readIndex;
  final WriteLyricIndex writeIndex;
  final ReadLyricFingerprint fingerprintFor;
  final ReadLocalLyricLines lyricLinesFor;
  final int workerCount;

  final Map<String, LyricIndexEntry> entries = {};
  LyricIndexProgress progress = const LyricIndexProgress();

  bool _loaded = false;
  Future<void>? _loadFuture;

  LyricSearchIndex({
    required this.readIndex,
    required this.writeIndex,
    required this.fingerprintFor,
    required this.lyricLinesFor,
    this.workerCount = 4,
  });

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final contents = await readIndex();
      final loadedEntries = <String, LyricIndexEntry>{};
      if (contents != null) {
        final envelope = Map<String, dynamic>.from(
          jsonDecode(contents) as Map,
        );
        if (envelope['version'] != formatVersion) {
          throw FormatException(
            'Unsupported lyric index version: ${envelope['version']}',
          );
        }
        final encodedEntries = Map<String, dynamic>.from(
          envelope['entries'] as Map,
        );
        for (final encodedEntry in encodedEntries.entries) {
          loadedEntries[encodedEntry.key] = LyricIndexEntry.fromJson(
            Map<String, dynamic>.from(encodedEntry.value as Map),
          );
        }
      }
      entries
        ..clear()
        ..addAll(loadedEntries);
      progress = const LyricIndexProgress();
    } catch (error) {
      entries.clear();
      progress = LyricIndexProgress(error: error);
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> sync(Iterable<Audio> audios) async {
    final audioList = audios.toList(growable: false);
    final availablePaths = audioList.map((audio) => audio.path).toSet();
    entries.removeWhere((path, _) => !availablePaths.contains(path));

    Object? syncError;
    progress = const LyricIndexProgress(isSyncing: true);
    notifyListeners();

    final queue = <_PendingLyricEntry>[];
    for (final audio in audioList) {
      try {
        final fingerprint = await fingerprintFor(audio);
        if (entries[audio.path]?.fingerprint != fingerprint) {
          queue.add(_PendingLyricEntry(audio, fingerprint));
        }
      } catch (error) {
        syncError = error;
      }
    }

    var processed = 0;
    progress = LyricIndexProgress(
      total: queue.length,
      isSyncing: true,
      error: syncError,
    );

    var nextIndex = 0;
    Future<void> runWorker() async {
      while (nextIndex < queue.length) {
        final pending = queue[nextIndex++];
        try {
          final lines = await lyricLinesFor(pending.audio);
          entries[pending.audio.path] = LyricIndexEntry(
            audioPath: pending.audio.path,
            fingerprint: pending.fingerprint,
            lines: lines,
          );
        } catch (error) {
          syncError = error;
        } finally {
          processed++;
          progress = LyricIndexProgress(
            processed: processed,
            total: queue.length,
            isSyncing: true,
            error: syncError,
          );
          if (processed % 25 == 0) notifyListeners();
        }
      }
    }

    if (queue.isNotEmpty) {
      final activeWorkers = min(max(workerCount, 1), queue.length);
      await Future.wait([
        for (var worker = 0; worker < activeWorkers; worker++) runWorker(),
      ]);
    }

    try {
      await writeIndex(
        jsonEncode({
          'version': formatVersion,
          'entries': {
            for (final entry in entries.entries)
              entry.key: entry.value.toJson(),
          },
        }),
      );
    } catch (error) {
      syncError = error;
    }

    progress = LyricIndexProgress(
      processed: processed,
      total: queue.length,
      error: syncError,
    );
    notifyListeners();
  }

  List<LyricSearchMatch> search(String query, Iterable<Audio> audios) =>
      searchLyricEntries(query: query, entries: entries, audios: audios);
}

class _PendingLyricEntry {
  final Audio audio;
  final LyricFileFingerprint fingerprint;

  const _PendingLyricEntry(this.audio, this.fingerprint);
}
