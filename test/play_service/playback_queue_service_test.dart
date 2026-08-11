import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/play_service/playback_queue_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio makeAudio(String path) => Audio(
      path,
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

void main() {
  late Directory directory;
  late LocalJsonStore store;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coriander-queue-');
    store = LocalJsonStore(directory);
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('persists a de-duplicated queue and restores its current position',
      () async {
    final first = makeAudio('D:/music/first.flac');
    final second = makeAudio('D:/music/second.flac');
    final queue = PlaybackQueueService(store: store);

    await queue.setQueue(
      [first, second, first],
      currentPath: second.path,
      position: const Duration(seconds: 42),
    );

    final saved = jsonDecode(
      await File(
              '${directory.path}${Platform.pathSeparator}playback_queue.json')
          .readAsString(),
    );
    expect(saved, {
      'version': 1,
      'items': [first.path, second.path],
      'currentPath': second.path,
      'positionMs': 42000,
    });

    final restored = PlaybackQueueService(store: store);
    await restored.load([first, second]);

    expect(restored.items, [first, second]);
    expect(restored.currentPath, second.path);
    expect(restored.currentIndex, 1);
    expect(restored.savedPosition, const Duration(seconds: 42));
  });

  test('drops missing and duplicate paths while loading legacy queue data',
      () async {
    final available = makeAudio('D:/music/available.flac');
    await store.writeAtomically('playback_queue.json', {
      'items': [
        'D:/music/missing.flac',
        available.path,
        available.path,
      ],
      'currentPath': 'D:/music/missing.flac',
      'positionMs': 1234,
    });

    final queue = PlaybackQueueService(store: store);
    await queue.load([available]);

    expect(queue.items, [available]);
    expect(queue.currentPath, isNull);
    expect(queue.currentIndex, -1);
    expect(queue.savedPosition, Duration.zero);
  });

  test('starts with an empty inert queue when optional recovery files corrupt',
      () async {
    final available = makeAudio('D:/music/available.flac');
    final primary = File(
      '${directory.path}${Platform.pathSeparator}playback_queue.json',
    );
    await File('${primary.path}.tmp').writeAsString('{unfinished write');
    await File('${primary.path}.bak').writeAsString('{invalid backup');

    final queue = PlaybackQueueService(store: store);

    await queue.load([available]);

    expect(queue.items, isEmpty);
    expect(queue.currentPath, isNull);
    expect(queue.savedPosition, Duration.zero);
  });

  test('edits the queue without duplicates and keeps current song consistent',
      () async {
    final first = makeAudio('D:/music/first.flac');
    final second = makeAudio('D:/music/second.flac');
    final third = makeAudio('D:/music/third.flac');
    final queue = PlaybackQueueService(store: store);

    await queue.setQueue([first, third], currentPath: first.path);
    expect(await queue.insertNext(second), isTrue);
    expect(await queue.append(first), isFalse);
    expect(queue.items, [first, second, third]);

    await queue.reorder(0, 3);
    expect(queue.items, [second, third, first]);
    expect(queue.currentIndex, 2);

    expect(await queue.removeAt(2), isTrue);
    expect(queue.currentPath, isNull);
    expect(queue.savedPosition, Duration.zero);

    await queue.clear();
    expect(queue.items, isEmpty);
  });

  test('retains an inserted next song when leaving shuffle mode', () async {
    final first = makeAudio('D:/music/first.flac');
    final next = makeAudio('D:/music/next.flac');
    final last = makeAudio('D:/music/last.flac');
    final queue = PlaybackQueueService(store: store);

    await queue.setQueue([first, last], currentPath: first.path);
    await queue.insertNext(next);

    final playlistBackup = queueSnapshotForShuffleRestore(queue.items);
    final shuffled = List<Audio>.from(queue.items.reversed);
    expect(shuffled, [last, next, first]);

    final restored = queueSnapshotForShuffleRestore(playlistBackup);
    expect(restored, [first, next, last]);
  });

  test('appends through the playback command once and persists the queue',
      () async {
    final first = makeAudio('D:/music/first.flac');
    final appended = makeAudio('D:/music/appended.flac');
    final queue = PlaybackQueueService(store: store);
    await queue.setQueue([first], currentPath: first.path);

    expect(await appendToPlaybackQueue(queue, appended), isTrue);
    expect(await appendToPlaybackQueue(queue, appended), isFalse);

    final restored = PlaybackQueueService(store: store);
    await restored.load([first, appended]);
    expect(restored.items, [first, appended]);
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
