import 'dart:async';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/library_update_coordinator.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _ThemeApi()));

  test('staged cancellation keeps the live index even if the scanner finishes',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('library-cancel-test-');
    addTearDown(() => directory.delete(recursive: true));
    final live = await File('${directory.path}/index.json')
        .writeAsString('{"roots":["old"],"folders":[]}');
    final entered = Completer<Directory>();
    final finish = Completer<void>();
    final coordinator = LibraryUpdateCoordinator.staged(
      indexDirectory: Future.value(directory),
      folders: ['new'],
      buildIndex: ({required folders, required indexPath}) async* {
        entered.complete(Directory(indexPath));
        await finish.future;
        await File('$indexPath/index.json')
            .writeAsString('{"roots":["new"],"folders":[]}');
      },
      reconcileAppData: () async => fail('Must not reconcile a cancelled scan'),
      refreshLyrics: () async =>
          fail('Must not refresh lyrics after cancellation'),
    );
    final run = coordinator.update();
    final staging = await entered.future;
    await coordinator.cancel();
    expect(await File('${staging.path}/.scan-cancel').exists(), isTrue);
    finish.complete();
    await run;
    expect(coordinator.progress.phase, LibraryUpdatePhase.cancelled);
    expect(await live.readAsString(), '{"roots":["old"],"folders":[]}');
    expect(await staging.exists(), isFalse);
  });

  test('validates staging before replacing the live file and refreshing data',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('library-publish-test-');
    addTearDown(() => directory.delete(recursive: true));
    final live = await File('${directory.path}/index.json')
        .writeAsString('{"roots":["old"],"folders":[]}');
    Future<void> run(String staged) => LibraryUpdateCoordinator.staged(
          indexDirectory: Future.value(directory),
          folders: ['new'],
          buildIndex: ({required folders, required indexPath}) async* {
            await File('$indexPath/index.json').writeAsString(staged);
          },
          reconcileAppData: () async {
            expect(AudioLibrary.instance.scanRoots, ['new']);
            expect(await live.readAsString(), staged);
          },
          refreshLyrics: () async {},
        ).update();

    await expectLater(run('{bad'), throwsFormatException);
    expect(await live.readAsString(), '{"roots":["old"],"folders":[]}');
    await run('{"roots":["new"],"folders":[]}');
    expect(await live.readAsString(), '{"roots":["new"],"folders":[]}');
  });
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

  test('surfaces a legacy-rebuild error without reconciling app data',
      () async {
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

class _ThemeApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    return super.noSuchMethod(invocation);
  }
}
