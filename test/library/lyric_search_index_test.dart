import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/ttml.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

const wordTimedTtml = '''
<tt xmlns="http://www.w3.org/ns/ttml"
    xmlns:itunes="http://music.apple.com/lyric-ttml-internal"
    itunes:timing="Word">
  <body><div>
    <p begin="19.311" end="22.288">
      <span begin="19.311" end="19.720">first</span>
      <span begin="19.720" end="20.491">second</span>
      <span begin="20.491" end="21.126">third</span>
    </p>
  </div></body>
</tt>
''';

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

  test('indexes TTML sync lines as searchable full lines', () {
    final lyric = Ttml.fromTtmlText(wordTimedTtml)!;
    final lines = lyricSearchLinesFromLyric(lyric);

    expect(lines, [
      const LyricSearchLine(startMs: 19311, text: 'firstsecondthird'),
    ]);
  });

  test('extracts LRC translations and sync lyric translations', () {
    final lrc = Lrc.fromLrcText(
      '[00:01.50]主句┃translation',
      LrcSource.local,
      separator: null,
    )!;
    final syncLine = TtmlLine(
      const Duration(milliseconds: 2500),
      const Duration(seconds: 1),
      const [],
      'timed main',
    )..translation = 'timed translation';
    final syncLyric = Ttml([syncLine]);

    expect(lyricSearchLinesFromLyric(lrc), [
      LyricSearchLine(
        startMs: 1500,
        text: '主句',
        translation: 'translation',
      ),
    ]);
    expect(lyricSearchLinesFromLyric(syncLyric), [
      LyricSearchLine(
        startMs: 2500,
        text: 'timed main',
        translation: 'timed translation',
      ),
    ]);
  });

  test('v1 indexes are rebuilt as v2 with persisted search forms', () async {
    String? persisted = jsonEncode({
      'version': 1,
      'entries': {
        'legacy.flac': LyricIndexEntry(
          audioPath: 'legacy.flac',
          fingerprint: const LyricFileFingerprint(audioModified: 1),
          lines: const [LyricSearchLine(startMs: 0, text: 'legacy')],
        ).toJson(),
      },
    });
    final loadedPaths = <String>[];
    final index = LyricSearchIndex(
      readIndex: () async => persisted,
      writeIndex: (contents) async => persisted = contents,
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (audio) async {
        loadedPaths.add(audio.path);
        return [LyricSearchLine(startMs: 5, text: audio.path)];
      },
    );
    final songs = [makeAudio('legacy.flac', 1), makeAudio('new.flac', 1)];

    await index.load();
    await index.sync(songs);

    final envelope = jsonDecode(persisted!) as Map<String, dynamic>;
    final entries = envelope['entries'] as Map<String, dynamic>;
    final firstLine =
        entries['legacy.flac']['lines'][0] as Map<String, dynamic>;
    expect(loadedPaths, ['legacy.flac', 'new.flac']);
    expect(envelope['version'], 2);
    expect(firstLine['searchForms'], isNotEmpty);
  });

  test('local lyric fingerprint tracks sidecar changes and deletion', () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_lyric_index_');
    addTearDown(() => directory.delete(recursive: true));
    final audioFile =
        File('${directory.path}${Platform.pathSeparator}song.flac');
    final sidecar = File('${directory.path}${Platform.pathSeparator}song.lrc');
    await audioFile.writeAsString('audio');
    await sidecar.writeAsString('[00:01.00]first');
    await sidecar.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final audio = makeAudio(audioFile.path, 42);

    final initial = await readLocalLyricFingerprint(audio);
    expect(initial.audioModified, 42);
    expect(initial.sidecarPath, sidecar.path);
    expect(initial.sidecarModified, 1000);

    await sidecar.writeAsString('[00:02.00]changed');
    await sidecar.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final changed = await readLocalLyricFingerprint(audio);
    expect(changed.sidecarModified, 2000);

    await sidecar.delete();
    final deleted = await readLocalLyricFingerprint(audio);
    expect(deleted.sidecarPath, isNull);
    expect(deleted.sidecarModified, isNull);
  });

  test('atomic index writes replace valid JSON without temporary files',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_lyric_index_');
    addTearDown(() => directory.delete(recursive: true));
    await writeLyricIndexAtomically(directory, '{"version":0}');

    await writeLyricIndexAtomically(
      directory,
      '{"version":1,"entries":{}}',
    );

    final finalFile = File(
      '${directory.path}${Platform.pathSeparator}lyric_search_index.json',
    );
    expect(jsonDecode(await finalFile.readAsString()), {
      'version': 1,
      'entries': <String, Object?>{},
    });
    expect(
      directory.listSync().map((entity) => entity.uri.pathSegments.last),
      ['lyric_search_index.json'],
    );
    expect(
      File('${finalFile.path}.tmp').existsSync(),
      isFalse,
    );
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
    expect(jsonDecode(persisted!)['version'], 2);
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
          'version': 2,
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
        'version': 2,
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
      'version': 2,
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
      'version': 2,
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
