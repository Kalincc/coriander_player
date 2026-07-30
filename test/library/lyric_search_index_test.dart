import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

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
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('sync reads only new or changed songs and removes deleted songs',
      () async {
    String? persisted;
    final loads = <String>[];
    final fingerprints = <String, LyricFileFingerprint>{
      'a.flac': const LyricFileFingerprint(audioModified: 1),
      'b.flac': const LyricFileFingerprint(audioModified: 1),
    };
    final index = LyricSearchIndex(
      readIndex: () async => persisted,
      writeIndex: (contents) async => persisted = contents,
      fingerprintFor: (audio) async => fingerprints[audio.path]!,
      lyricLinesFor: (audio) async {
        loads.add(audio.path);
        return [LyricSearchLine(startMs: 0, text: audio.path)];
      },
      workerCount: 2,
    );

    await index.load();
    await index.sync([makeAudio('a.flac', 1), makeAudio('b.flac', 1)]);
    expect(loads, containsAll(['a.flac', 'b.flac']));

    loads.clear();
    await index.sync([makeAudio('a.flac', 1)]);
    expect(loads, isEmpty);
    expect(index.entries.keys, ['a.flac']);

    fingerprints['a.flac'] = const LyricFileFingerprint(audioModified: 2);
    await index.sync([makeAudio('a.flac', 2)]);
    expect(loads, ['a.flac']);
    expect(jsonDecode(persisted!)['version'], 1);
  });

  test('corrupt JSON resets to an empty usable index', () async {
    final index = LyricSearchIndex(
      readIndex: () async => '{broken',
      writeIndex: (_) async {},
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    );
    await index.load();
    expect(index.entries, isEmpty);
    expect(index.progress.error, isNotNull);
  });

  test('one lyric read failure does not stop remaining songs', () async {
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (audio) async {
        if (audio.path == 'bad.flac') {
          throw const FormatException('bad lyric');
        }
        return const [LyricSearchLine(startMs: 1, text: 'ok')];
      },
    );
    await index.load();
    await index.sync([
      makeAudio('bad.flac', 1),
      makeAudio('good.flac', 1),
    ]);
    expect(index.entries['good.flac']!.lines.single.text, 'ok');
    expect(index.progress.processed, 2);
  });

  test('save failure keeps searchable in-memory entries', () async {
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async => throw const FileSystemException('disk full'),
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async =>
          const [LyricSearchLine(startMs: 1, text: 'needle')],
    );
    await index.load();
    final song = makeAudio('song.flac', 1);
    await index.sync([song]);
    expect(index.search('needle', [song]), hasLength(1));
    expect(index.progress.error, isNotNull);
  });

  test('load accepts the versioned envelope and only reads it once', () async {
    var reads = 0;
    var notifications = 0;
    final index = LyricSearchIndex(
      readIndex: () async {
        reads++;
        return jsonEncode({
          'version': 1,
          'entries': {
            'song.flac': LyricIndexEntry(
              audioPath: 'song.flac',
              fingerprint: const LyricFileFingerprint(audioModified: 1),
              lines: const [
                LyricSearchLine(startMs: 12, text: 'loaded'),
              ],
            ).toJson(),
          },
        });
      },
      writeIndex: (_) async {},
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    )..addListener(() => notifications++);

    await index.load();
    index.entries['memory.flac'] = LyricIndexEntry(
      audioPath: 'memory.flac',
      fingerprint: const LyricFileFingerprint(audioModified: 2),
      lines: const [],
    );
    await index.load();

    expect(reads, 1);
    expect(index.entries.keys, containsAll(['song.flac', 'memory.flac']));
    expect(notifications, 1);
  });

  test('concurrent load calls share the first in-flight load', () async {
    var reads = 0;
    final readCompleter = Completer<String?>();
    final index = LyricSearchIndex(
      readIndex: () {
        reads++;
        return readCompleter.future;
      },
      writeIndex: (_) async {},
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    );

    final firstLoad = index.load();
    final secondLoad = index.load();
    expect(reads, 1);
    var secondCompleted = false;
    secondLoad.then((_) => secondCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(secondCompleted, isFalse);
    readCompleter.complete(null);
    await Future.wait([firstLoad, secondLoad]);
    expect(secondCompleted, isTrue);
  });

  test('version mismatch clears entries, records an error, and notifies',
      () async {
    var notifications = 0;
    final index = LyricSearchIndex(
      readIndex: () async => jsonEncode({
        'version': 99,
        'entries': <String, Object?>{},
      }),
      writeIndex: (_) async {},
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    )..addListener(() => notifications++);

    await index.load();

    expect(index.entries, isEmpty);
    expect(index.progress.error, isNotNull);
    expect(notifications, 1);
  });

  test('load rejects an envelope with unexpected top-level keys', () async {
    final index = LyricSearchIndex(
      readIndex: () async => jsonEncode({
        'version': 1,
        'entries': {
          'song.flac': LyricIndexEntry(
            audioPath: 'song.flac',
            fingerprint: const LyricFileFingerprint(audioModified: 1),
            lines: const [LyricSearchLine(startMs: 0, text: 'must reject')],
          ).toJson(),
        },
        'unexpected': true,
      }),
      writeIndex: (_) async {},
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    );

    await index.load();

    expect(index.entries, isEmpty);
    expect(index.progress.error, isA<FormatException>());
  });

  test('deletion-only sync persists the exact versioned envelope', () async {
    String? persisted = jsonEncode({
      'version': 1,
      'entries': {
        'deleted.flac': LyricIndexEntry(
          audioPath: 'deleted.flac',
          fingerprint: const LyricFileFingerprint(audioModified: 1),
          lines: const [LyricSearchLine(startMs: 0, text: 'gone')],
        ).toJson(),
      },
    });
    final index = LyricSearchIndex(
      readIndex: () async => persisted,
      writeIndex: (contents) async => persisted = contents,
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    );

    await index.load();
    await index.sync(const []);

    expect(jsonDecode(persisted!), {
      'version': 1,
      'entries': <String, Object?>{},
    });
  });

  test('sync never exceeds the configured worker bound', () async {
    var active = 0;
    var maxActive = 0;
    final gates = <Completer<void>>[];
    final allStarted = Completer<void>();
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async {
        active++;
        if (active > maxActive) maxActive = active;
        final gate = Completer<void>();
        gates.add(gate);
        if (gates.length == 2) allStarted.complete();
        await gate.future;
        active--;
        return const [];
      },
      workerCount: 2,
    );
    await index.load();

    final syncing = index.sync([
      makeAudio('1.flac', 1),
      makeAudio('2.flac', 1),
      makeAudio('3.flac', 1),
    ]);
    await allStarted.future;
    expect(gates, hasLength(2));
    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(gates, hasLength(3));
    gates[1].complete();
    gates[2].complete();
    await syncing;

    expect(maxActive, 2);
  });

  test('a later deletion-only sync cannot be overtaken by an older sync',
      () async {
    final lyricStarted = Completer<void>();
    final releaseLyric = Completer<void>();
    final persistedEntries = <Set<String>>[];
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (contents) async {
        final envelope = jsonDecode(contents) as Map<String, dynamic>;
        final encodedEntries = envelope['entries'] as Map<String, dynamic>;
        persistedEntries.add(encodedEntries.keys.toSet());
      },
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async {
        lyricStarted.complete();
        await releaseLyric.future;
        return const [LyricSearchLine(startMs: 0, text: 'indexed')];
      },
      workerCount: 1,
    );
    await index.load();

    final olderSync = index.sync([makeAudio('old.flac', 1)]);
    await lyricStarted.future;
    final newerSync = index.sync(const []);
    var newerCompleted = false;
    newerSync.then((_) => newerCompleted = true);
    await Future<void>.delayed(Duration.zero);
    final completedBeforeOlderSync = newerCompleted;

    releaseLyric.complete();
    await Future.wait([olderSync, newerSync]);

    expect(completedBeforeOlderSync, isFalse);
    expect(index.entries, isEmpty);
    expect(persistedEntries, [
      {'old.flac'},
      <String>{},
    ]);
  });

  test('overlapping sync calls share the service worker bound', () async {
    var active = 0;
    var maxActive = 0;
    final gates = <Completer<void>>[];
    final firstTwoStarted = Completer<void>();
    final allFourStarted = Completer<void>();
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async {
        active++;
        if (active > maxActive) maxActive = active;
        final gate = Completer<void>();
        gates.add(gate);
        if (gates.length == 2) firstTwoStarted.complete();
        if (gates.length == 4) allFourStarted.complete();
        await gate.future;
        active--;
        return const [];
      },
      workerCount: 2,
    );
    await index.load();

    final firstSync = index.sync([
      makeAudio('first-a.flac', 1),
      makeAudio('first-b.flac', 1),
    ]);
    await firstTwoStarted.future;
    final secondSync = index.sync([
      makeAudio('second-a.flac', 1),
      makeAudio('second-b.flac', 1),
    ]);
    await Future<void>.delayed(Duration.zero);
    final activeBeforeFirstCompleted = active;
    gates[0].complete();
    gates[1].complete();
    await allFourStarted.future;
    gates[2].complete();
    gates[3].complete();
    await Future.wait([firstSync, secondSync]);

    expect(activeBeforeFirstCompleted, 2);
    expect(maxActive, 2);
  });

  for (final workerCount in [0, -2]) {
    test('workerCount $workerCount still makes progress', () async {
      final index = LyricSearchIndex(
        readIndex: () async => null,
        writeIndex: (_) async {},
        fingerprintFor: (audio) async =>
            LyricFileFingerprint(audioModified: audio.modified),
        lyricLinesFor: (_) async =>
            const [LyricSearchLine(startMs: 0, text: 'indexed')],
        workerCount: workerCount,
      );
      await index.load();

      await index.sync([makeAudio('song.flac', 1)]);

      expect(index.entries, contains('song.flac'));
      expect(index.progress.processed, 1);
    });
  }

  test('fingerprint failure is isolated from remaining songs', () async {
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async {
        if (audio.path == 'bad.flac') {
          throw const FileSystemException('cannot stat');
        }
        return LyricFileFingerprint(audioModified: audio.modified);
      },
      lyricLinesFor: (_) async =>
          const [LyricSearchLine(startMs: 0, text: 'ok')],
    );
    await index.load();

    await index.sync([
      makeAudio('bad.flac', 1),
      makeAudio('good.flac', 1),
    ]);

    expect(index.entries, contains('good.flac'));
    expect(index.progress.error, isA<FileSystemException>());
  });

  test('sync notifies at each 25-song checkpoint and at completion', () async {
    final snapshots = <LyricIndexProgress>[];
    late LyricSearchIndex index;
    index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async => const [],
      workerCount: 1,
    )..addListener(() => snapshots.add(index.progress));
    await index.load();
    snapshots.clear();

    await index.sync([
      for (var i = 0; i < 26; i++) makeAudio('$i.flac', 1),
    ]);

    expect(
      snapshots,
      contains(
        isA<LyricIndexProgress>()
            .having((value) => value.processed, 'processed', 25)
            .having((value) => value.isSyncing, 'isSyncing', isTrue),
      ),
    );
    expect(snapshots.last.processed, 26);
    expect(snapshots.last.total, 26);
    expect(snapshots.last.isSyncing, isFalse);
  });
}

class _TestRustLibApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(
        fore: (255, 0, 0, 0),
        accent: (255, 0, 0, 0),
      );
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
