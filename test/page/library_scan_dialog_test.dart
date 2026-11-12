import 'dart:async';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/page/settings_page/page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _ThemeApi()));

  testWidgets('settings sections remain reachable at minimum window width',
      (tester) async {
    tester.view.physicalSize = const Size(507, 507);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPage())));
    for (final heading in ['播放', '歌词', '外观', '音乐库', '存储与诊断', '更新']) {
      await tester.scrollUntilVisible(find.text(heading), 100);
      expect(find.text(heading), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'a background scan survives closing the dialog and can be cancelled',
      (tester) async {
    late Directory directory;
    late Future<Directory> dataDirectory;
    late StreamController<IndexActionState> scan;
    late Completer<String> started;
    const oldIndex = '{"roots":["D:/music"],"folders":[]}';
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('library-dialog-');
      addTearDown(() => directory.delete(recursive: true));
      final index =
          await File('${directory.path}/index.json').writeAsString(oldIndex);
      await AudioLibrary.initFromIndex(indexFile: index);
      dataDirectory = Future.value(directory);
      scan = StreamController<IndexActionState>();
      started = Completer<String>();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return Column(children: [
          const LibrarySettings(),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AudioLibraryEditorDialog(
                applicationSupportDirectory: dataDirectory,
                buildIndex: ({required folders, required indexPath}) {
                  started.complete(indexPath);
                  return scan.stream;
                },
              ),
            ),
            child: const Text('打开文件夹管理'),
          ),
        ]);
      })),
    ));
    final open = find.text('打开文件夹管理');
    await tester.tap(open);
    await tester.pumpAndSettle();
    late String staging;
    await tester.runAsync(() async {
      await tester.tap(find.text('立即扫描'));
      staging = await started.future.timeout(const Duration(seconds: 3));
    });
    await tester.runAsync(() async {
      scan.add(const IndexActionState(progress: -1, message: '已检查 30 个文件'));
    });
    await tester.pump();
    expect(find.text('已检查 30 个文件'), findsOneWidget);
    await tester.tap(find.text('后台继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('管理文件夹'), findsNothing);
    expect(find.text('扫描期间暂不能修改艺术家分隔符'), findsOneWidget);

    await tester.tap(open);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已检查 30 个文件'), findsOneWidget);
    expect(find.text('立即扫描'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('取消扫描'));
      final marker = File('$staging/.scan-cancel');
      await _waitUntil(marker.exists);
      await scan.close();
      await _waitUntil(() async => !await Directory(staging).exists());
      expect(
          await File('${directory.path}/index.json').readAsString(), oldIndex);
    });
    await tester.pump();
    expect(find.text('扫描已取消，原音乐库保持不变'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _waitUntil(Future<bool> Function() check) async {
  final watch = Stopwatch()..start();
  while (!await check()) {
    if (watch.elapsed >= const Duration(seconds: 3)) {
      throw TimeoutException('Scan state did not change');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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
