import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/updating_page.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('existing-index startup only loads persisted state', () async {
    final events = <String>[];
    final loader = LibraryStartupLoader(
      reloadLibrary: () async => events.add('library'),
      loadPlaylists: () async => events.add('playlists'),
      loadLyricSources: () async => events.add('lyric sources'),
      loadLyricIndex: () async => events.add('lyric index'),
      loadPlaybackHistory: () async => events.add('history'),
    );

    await loader.load();

    expect(events, [
      'library',
      'playlists',
      'lyric sources',
      'lyric index',
      'history',
    ]);
  });

  testWidgets('corrupt library index remains visible as a startup error',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdatingStateView(
            indexPath: Directory.systemTemp,
            loadLibrary: () async => throw const FormatException('bad index'),
            onUpdated: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('library-startup-error')), findsOneWidget);
    expect(find.textContaining('bad index'), findsOneWidget);
    expect(completed, isFalse);
  });

  testWidgets('legacy library requires selecting roots before manual scan',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_legacy_editor_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'folders': <Object>[],
    }));
    await AudioLibrary.initFromIndex(indexFile: indexFile);

    await tester.pumpWidget(
      MaterialApp(
        home: AudioLibraryEditorDialog(
          applicationSupportDirectory: Future.value(directory),
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const Key('legacy-library-roots-warning')), findsOneWidget);
    final scanButton = tester.widget<TextButton>(
      find.byKey(const Key('scan-library-now-button')),
    );
    expect(scanButton.onPressed, isNull);
    final confirmButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '确定'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('manual scan rebuilds recursively from configured roots',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_manual_scan_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'roots': ['D:/Music'],
      'folders': <Object>[],
    }));
    await AudioLibrary.initFromIndex(indexFile: indexFile);
    List<String>? scannedRoots;
    String? scannedIndexPath;

    await tester.pumpWidget(
      MaterialApp(
        home: AudioLibraryEditorDialog(
          applicationSupportDirectory: Future.value(directory),
          buildIndex: ({required folders, required indexPath}) {
            scannedRoots = List.of(folders);
            scannedIndexPath = indexPath;
            return Stream<IndexActionState>.error(
                StateError('stop after scan'));
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-library-now-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(scannedRoots, ['D:/Music']);
    expect(scannedIndexPath, directory.path);
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
