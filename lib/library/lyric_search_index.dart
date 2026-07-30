import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

typedef ReadLyricIndex = Future<String?> Function();
typedef WriteLyricIndex = Future<void> Function(String contents);
typedef ReadLyricFingerprint = Future<LyricFileFingerprint> Function(
  Audio audio,
);
typedef ReadLocalLyricLines = Future<List<LyricSearchLine>> Function(
  Audio audio,
);

Future<LyricFileFingerprint> readLocalLyricFingerprint(Audio audio) async {
  final sidecarPath = path.setExtension(audio.path, '.lrc');
  final sidecar = File(sidecarPath);
  final exists = await sidecar.exists();
  return LyricFileFingerprint(
    audioModified: audio.modified,
    sidecarPath: exists ? sidecarPath : null,
    sidecarModified:
        exists ? (await sidecar.lastModified()).millisecondsSinceEpoch : null,
  );
}

Future<List<LyricSearchLine>> readLocalLyricLines(Audio audio) async {
  final lyric = await Lrc.fromAudioPath(audio);
  if (lyric == null) return const [];
  return lyric.lines
      .whereType<UnsyncLyricLine>()
      .where((line) => line.content.trim().isNotEmpty)
      .map((line) => LyricSearchLine(
            startMs: line.start.inMilliseconds,
            text: line.content,
          ))
      .toList(growable: false);
}

Future<void> writeLyricIndexAtomically(
  Directory directory,
  String contents,
) async {
  final indexFile = File(
    path.join(directory.path, 'lyric_search_index.json'),
  );
  final temporaryFile = File(
    path.join(directory.path, 'lyric_search_index.json.tmp'),
  );
  final backupFile = File(
    path.join(directory.path, 'lyric_search_index.json.bak'),
  );
  var movedCurrentToBackup = false;

  try {
    await temporaryFile.writeAsString(contents, flush: true);
    if (await indexFile.exists()) {
      await indexFile.rename(backupFile.path);
      movedCurrentToBackup = true;
    }
    await temporaryFile.rename(indexFile.path);
    if (movedCurrentToBackup) await backupFile.delete();
  } catch (_) {
    if (movedCurrentToBackup && await backupFile.exists()) {
      if (await indexFile.exists()) await indexFile.delete();
      await backupFile.rename(indexFile.path);
    }
    rethrow;
  }
}

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
  static final LyricSearchIndex instance = LyricSearchIndex.defaults();

  final ReadLyricIndex readIndex;
  final WriteLyricIndex writeIndex;
  final ReadLyricFingerprint fingerprintFor;
  final ReadLocalLyricLines lyricLinesFor;
  final int workerCount;

  final Map<String, LyricIndexEntry> entries = {};
  LyricIndexProgress progress = const LyricIndexProgress();

  bool _loaded = false;
  Future<void>? _loadFuture;
  Future<void> _syncTail = Future.value();

  LyricSearchIndex({
    required this.readIndex,
    required this.writeIndex,
    required this.fingerprintFor,
    required this.lyricLinesFor,
    this.workerCount = 4,
  });

  factory LyricSearchIndex.defaults() => LyricSearchIndex(
        readIndex: () async {
          final directory = await getAppDataDir();
          final file = File(
            path.join(directory.path, 'lyric_search_index.json'),
          );
          return await file.exists() ? file.readAsString() : null;
        },
        writeIndex: (contents) async {
          final directory = await getAppDataDir();
          await writeLyricIndexAtomically(directory, contents);
        },
        fingerprintFor: readLocalLyricFingerprint,
        lyricLinesFor: readLocalLyricLines,
        workerCount: 4,
      );

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
        if (envelope.length != 2 ||
            !envelope.containsKey('version') ||
            !envelope.containsKey('entries')) {
          throw const FormatException('Invalid lyric index envelope');
        }
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

  Future<void> sync(Iterable<Audio> audios) {
    final audioList = audios.toList(growable: false);
    final previousSync = _syncTail;
    final releaseNextSync = Completer<void>();
    _syncTail = releaseNextSync.future;
    return _runSyncAfter(previousSync, releaseNextSync, audioList);
  }

  Future<void> refreshCurrentLibrary() async {
    await load();
    unawaited(sync(AudioLibrary.instance.audioCollection));
  }

  Future<void> _runSyncAfter(
    Future<void> previousSync,
    Completer<void> releaseNextSync,
    List<Audio> audioList,
  ) async {
    await previousSync;
    try {
      await _sync(audioList);
    } finally {
      releaseNextSync.complete();
    }
  }

  Future<void> _sync(List<Audio> audioList) async {
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
