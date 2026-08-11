import 'dart:async';

import 'package:coriander_player/library/library_update_coordinator.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('updates the library before reconciling data and refreshing lyrics',
      () async {
    final events = <String>[];
    final coordinator = LibraryUpdateCoordinator(
      scan: () async => Stream.fromIterable([
        const IndexActionState(progress: 0.5, message: '正在更新'),
      ]).map((state) {
        events.add('scan');
        return state;
      }),
      reloadLibrary: () async => events.add('reload'),
      reconcileAppData: () async => events.add('reconcile'),
      refreshLyrics: () async => events.add('lyrics'),
    );

    await coordinator.update();

    expect(events, ['scan', 'reload', 'reconcile', 'lyrics']);
    expect(coordinator.progress.isUpdating, isFalse);
    expect(coordinator.progress.error, isNull);
  });

  test('keeps existing data untouched when scanning fails', () async {
    final events = <String>[];
    final coordinator = LibraryUpdateCoordinator(
      scan: () async =>
          Stream<IndexActionState>.error(StateError('scan failed')),
      reloadLibrary: () async => events.add('reload'),
      reconcileAppData: () async => events.add('reconcile'),
      refreshLyrics: () async => events.add('lyrics'),
    );

    await expectLater(coordinator.update(), throwsStateError);

    expect(events, isEmpty);
    expect(coordinator.progress.error, isA<StateError>());
    expect(coordinator.progress.isUpdating, isFalse);
  });

  test('surfaces a legacy-rebuild error without reconciling app data', () async {
    final calls = <String>[];
    final coordinator = LibraryUpdateCoordinator(
      scan: () async => Stream<IndexActionState>.error(
        StateError('索引缺少扫描根目录，请在文件夹管理中执行完整重建。'),
      ),
      reloadLibrary: () async => calls.add('reload'),
      reconcileAppData: () async => calls.add('reconcile'),
      refreshLyrics: () async => calls.add('lyrics'),
    );

    await expectLater(coordinator.update(), throwsStateError);

    expect(calls, isEmpty);
    expect(coordinator.progress.error, isA<StateError>());
  });
}
