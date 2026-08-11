import 'dart:io';

import 'package:coriander_player/page/updating_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

}
