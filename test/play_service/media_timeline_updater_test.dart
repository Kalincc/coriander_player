import 'dart:async';

import 'package:coriander_player/play_service/media_timeline_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('30 Hz progress keeps one latest update per second',
      (tester) async {
    final sent = <int>[];
    final updater =
        MediaTimelineUpdater(send: (value) async => sent.add(value));
    addTearDown(updater.dispose);
    updater.update(0);
    await tester.pump();
    for (var i = 1; i <= 30; i++) {
      updater.update(i * 33);
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(sent, [0]);
    await tester.pump(const Duration(milliseconds: 10));
    expect(sent, [0, 990]);
    updater.dispose();
  });

  testWidgets('slow native calls never overlap or accumulate old positions',
      (tester) async {
    final sent = <int>[];
    final blocked = Completer<void>();
    final updater = MediaTimelineUpdater(send: (value) async {
      sent.add(value);
      if (value == 0) await blocked.future;
    });
    addTearDown(updater.dispose);
    updater.update(0);
    for (var i = 1; i <= 100; i++) {
      updater.update(i);
    }
    await tester.pump(const Duration(seconds: 3));
    expect(sent, [0]);
    blocked.complete();
    await tester.pump();
    expect(sent, [0, 100]);
    updater.update(4000, immediate: true);
    await tester.pump();
    expect(sent, [0, 100, 4000]);
    updater.dispose();
  });

  testWidgets('errors allow retry and disposal cancels deferred work',
      (tester) async {
    final sent = <int>[];
    final errors = <Object>[];
    final updater = MediaTimelineUpdater(
      send: (value) async {
        sent.add(value);
        if (value == 0) throw StateError('native failure');
      },
      onError: (error, _) => errors.add(error),
    );
    updater.update(0);
    await tester.pump();
    updater.update(1, immediate: true);
    await tester.pump();
    expect(sent, [0, 1]);
    expect(errors, hasLength(1));
    updater.update(2);
    updater.dispose();
    updater.update(3, immediate: true);
    await tester.pump(const Duration(seconds: 2));
    expect(sent, [0, 1]);
  });
}
