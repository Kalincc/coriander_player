import 'dart:async';
import 'dart:io';

import 'package:coriander_player/library/library_update_coordinator.dart';
import 'package:coriander_player/page/updating_page.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legacy rebuild action retries the update without playback',
      (tester) async {
    var scanAttempts = 0;
    var rebuildOpened = false;
    var completed = false;
    final coordinator = LibraryUpdateCoordinator(
      scan: () async {
        scanAttempts++;
        if (scanAttempts == 1) {
          return Stream<IndexActionState>.error(
            StateError(
              'index is missing configured scan roots; rebuild the library from folder management',
            ),
          );
        }
        return const Stream<IndexActionState>.empty();
      },
      reloadLibrary: () async {},
      reconcileAppData: () async {},
      refreshLyrics: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdatingStateView(
            indexPath: Directory.systemTemp,
            coordinatorFactory: (_) => coordinator,
            showRebuildDialog: (_) async {
              rebuildOpened = true;
              return true;
            },
            onUpdated: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('rebuild-library-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('rebuild-library-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(rebuildOpened, isTrue);
    expect(scanAttempts, 2);
    expect(completed, isTrue);
  });
}
