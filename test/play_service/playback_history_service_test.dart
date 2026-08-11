import 'dart:async';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio makeAudio(String path, {int duration = 180}) => Audio(
      path,
      'Artist',
      'Album',
      1,
      duration,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

void main() {
  late Directory directory;
  late DateTime now;
  late PlaybackHistoryService history;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coriander-history-');
    now = DateTime(2026, 8, 11, 12);
    history = PlaybackHistoryService(
      store: LocalJsonStore(directory),
      now: () => now,
    );
    await history.load();
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('records only sessions that reach the earliest effective threshold',
      () async {
    final long = makeAudio('D:/music/long.flac', duration: 180);
    history.startSession(long);
    history.recordPosition(const Duration(seconds: 29));
    await history.endSession();

    expect(history.events, isEmpty);

    history.startSession(long);
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();

    final short = makeAudio('D:/music/short.flac', duration: 40);
    history.startSession(short);
    history.recordPosition(const Duration(seconds: 20));
    await history.endSession();

    final unknown = makeAudio('D:/music/unknown.flac', duration: 0);
    history.startSession(unknown);
    history.recordPosition(Duration.zero);
    await history.endSession();

    expect(history.events.map((event) => event.path), [long.path, short.path]);
    expect(history.events.map((event) => event.listened), [
      const Duration(seconds: 30),
      const Duration(seconds: 20),
    ]);
  });

  test('finalizes pause sessions once and keeps newest twenty qualifying plays',
      () async {
    final audio = makeAudio('D:/music/repeated.flac');

    history.startSession(audio, startedAt: DateTime(2026, 8, 1, 10));
    history.recordPosition(const Duration(seconds: 32));
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();
    await history.endSession();

    history.startSession(audio, startedAt: DateTime(2026, 8, 1, 11));
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();

    for (var hour = 0; hour < 22; hour++) {
      history.startSession(
        audio,
        startedAt: DateTime(2026, 8, 2, hour),
      );
      history.recordPosition(const Duration(seconds: 30));
      await history.endSession();
    }

    expect(history.events, hasLength(24));
    expect(history.events.first.listened, const Duration(seconds: 32));
    expect(history.recent20, hasLength(20));
    expect(history.recent20.first.startedAt, DateTime(2026, 8, 2, 21));
    expect(history.recent20.last.startedAt, DateTime(2026, 8, 2, 2));
  });

  test('does not count pre-pause position in a resumed session', () async {
    final audio = makeAudio('D:/music/resumed.flac');

    history.startSession(audio);
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();

    history.startSession(
      audio,
      initialPosition: const Duration(seconds: 30),
    );
    history.recordPosition(const Duration(seconds: 31));
    await history.endSession();

    expect(history.events, hasLength(1));
    expect(history.events.single.listened, const Duration(seconds: 30));
  });

  test('does not count a seek jump as listened time', () async {
    final audio = makeAudio('D:/music/seeked.flac');

    history.startSession(audio);
    history.recordPosition(const Duration(seconds: 10));
    history.recordSeek(const Duration(minutes: 2));
    await history.endSession();

    expect(history.events, isEmpty);
  });

  test('finalizes history in memory before a delayed persistence completes',
      () async {
    final delayedStore = _DelayedStore(directory);
    final delayedHistory = PlaybackHistoryService(
      store: delayedStore,
      now: () => now,
    );
    final audio = makeAudio('D:/music/delayed-write.flac');

    delayedHistory.startSession(audio);
    delayedHistory.recordPosition(const Duration(seconds: 30));
    final completion = delayedHistory.endSession();
    var completed = false;
    completion.whenComplete(() => completed = true);

    expect(delayedHistory.events.map((event) => event.path), [audio.path]);
    await Future<void>.delayed(Duration.zero);
    expect(delayedStore.writeStarted, isTrue);
    expect(completed, isFalse);

    delayedStore.allowWrite();
    await completion;
  });

  test('nonblocking lifecycle finalization does not wait for persistence',
      () async {
    final delayedStore = _DelayedStore(directory);
    final delayedHistory = PlaybackHistoryService(
      store: delayedStore,
      now: () => now,
    );
    final audio = makeAudio('D:/music/nonblocking-finalize.flac');

    delayedHistory.startSession(audio);
    delayedHistory.recordPosition(const Duration(seconds: 30));
    finalizePlaybackHistorySession(delayedHistory);

    expect(delayedHistory.events.map((event) => event.path), [audio.path]);
    await Future<void>.delayed(Duration.zero);
    expect(delayedStore.writeStarted, isTrue);
    delayedStore.allowWrite();
  });

  test('removes records older than twelve months while loading', () async {
    final store = LocalJsonStore(directory);
    await store.writeAtomically('play_history.json', {
      'version': 1,
      'events': [
        {
          'path': 'D:/music/old.flac',
          'startedAt': '2025-08-10T12:00:00.000',
          'listenedMs': 30000,
          'qualified': true,
        },
        {
          'path': 'D:/music/kept.flac',
          'startedAt': '2025-08-11T12:00:00.000',
          'listenedMs': 30000,
          'qualified': true,
        },
      ],
    });

    await history.load();

    expect(history.events.map((event) => event.path), ['D:/music/kept.flac']);
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

class _DelayedStore extends LocalJsonStore {
  _DelayedStore(super.directory);

  final _writeGate = Completer<void>();
  var writeStarted = false;

  @override
  Future<void> writeAtomically(String fileName, Object value) async {
    writeStarted = true;
    await _writeGate.future;
  }

  void allowWrite() => _writeGate.complete();
}
