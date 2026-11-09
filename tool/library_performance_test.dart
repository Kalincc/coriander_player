// Opt-in benchmark: flutter test --no-pub tool/library_performance_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/listening_report.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/library/playback_history_models.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _ThemeApi()));
  test('synthetic library and history workload', () async {
    final directory = await Directory.systemTemp.createTemp('coriander-perf-');
    addTearDown(() => directory.delete(recursive: true));
    final index = File('${directory.path}/index.json');
    final audios = List.generate(
        20000,
        (i) => Audio('Song $i', '歌手 ${i ~/ 100}', '專輯 ${i ~/ 10}', i % 10 + 1,
            180, 320, 44100, 'D:/music/song-$i.flac', 0, 0, 'test'));
    await index.writeAsString(jsonEncode({
      'folders': [
        {
          'path': 'D:/music',
          'modified': 0,
          'latest': 0,
          'audios': audios.map((audio) => audio.toMap()).toList(),
        },
      ],
    }));
    final now = DateTime(2026, 11, 9, 12);
    final store = LocalJsonStore(directory);
    await store.writeAtomically('play_history.json', {
      'version': 1,
      'events': List.generate(
          50000,
          (i) => PlaybackHistoryEvent(
                  path: audios[i % audios.length].path,
                  startedAt: now.subtract(Duration(minutes: i * 5)),
                  listened: const Duration(minutes: 3),
                  qualified: true)
              .toMap()),
    });
    final history = PlaybackHistoryService(store: store, now: () => now);
    addTearDown(history.dispose);
    await history.load();
    final period = ReportPeriod.recentTwelveMonths(now);
    final metadata = {for (final audio in audios) audio.path: audio};

    await _measure(
        'index load', () => AudioLibrary.initFromIndex(indexFile: index));
    expect(AudioLibrary.instance.audioCollection.length, audios.length);
    await _measure('history save', () async {
      history.startSession(audios.first);
      history.recordPosition(const Duration(minutes: 3));
      await history.endSession();
    });
    await _measure('annual report', () {
      final report = buildListeningReport(history.events, period, metadata);
      expect(report.qualifiedPlayCount, history.events.length);
    });
  });
}

class _ThemeApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}

Future<void> _measure(String label, FutureOr<void> Function() work) async {
  final elapsed = <int>[];
  final gaps = <int>[];
  for (var i = 0; i <= 5; i++) {
    final clock = Stopwatch()..start();
    var last = 0;
    var longest = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
      final current = clock.elapsedMicroseconds;
      final gap = current - last;
      if (gap > longest) longest = gap;
      last = current;
    });
    try {
      final start = clock.elapsedMicroseconds;
      await work();
      if (i > 0) elapsed.add(clock.elapsedMicroseconds - start);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      if (i > 0) gaps.add(longest);
    } finally {
      timer.cancel();
    }
  }
  String medianMs(List<int> samples) =>
      ((samples..sort())[samples.length ~/ 2] / 1000).toStringAsFixed(1);
  debugPrint(
      '$label: ${medianMs(elapsed)} ms wall, ${medianMs(gaps)} ms max timer gap (medians)');
}
