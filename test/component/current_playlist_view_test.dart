import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:coriander_player/play_service/playback_queue_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path) => Audio(
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
  late PlaybackQueueService queue;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coriander-queue-ui-');
    queue = PlaybackQueueService(store: _MemoryStore(directory));
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  testWidgets('renders queue items', (tester) async {
    final first = _audio('D:/music/first.flac');
    await queue.setQueue([first], currentPath: first.path);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CurrentPlaylistView(queueService: queue)),
    ));

    expect(find.text(first.title), findsOneWidget);
  });

  testWidgets('removes and clears items through the queue service',
      (tester) async {
    final first = _audio('D:/music/first.flac');
    final second = _audio('D:/music/second.flac');
    await queue.setQueue([first, second], currentPath: first.path);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CurrentPlaylistView(queueService: queue)),
    ));

    expect(find.text(first.title), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from queue').first);
    await tester.pump();
    expect(queue.items, [second]);
    expect(queue.currentPath, isNull);

    await queue.setCurrent(audio: second, position: Duration.zero);
    await tester.tap(find.byTooltip('Clear queue'));
    await tester.pump();
    expect(queue.items, isEmpty);
    expect(queue.currentPath, isNull);
    expect(find.text('Queue is empty'), findsOneWidget);
  });

  testWidgets('uses the supplied callback when a queue item is tapped',
      (tester) async {
    final first = _audio('D:/music/first.flac');
    await queue.setQueue([first], currentPath: first.path);
    var selectedIndex = -1;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CurrentPlaylistView(
          queueService: queue,
          onPlayIndex: (index) => selectedIndex = index,
        ),
      ),
    ));

    await tester.tap(find.text(first.title));
    expect(selectedIndex, 0);
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

class _MemoryStore extends LocalJsonStore {
  _MemoryStore(super.directory);

  Object? _value;

  @override
  Future<Object?> read(String fileName) async => _value;

  @override
  Future<void> writeAtomically(String fileName, Object value) async {
    _value = value;
  }
}
