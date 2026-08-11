import 'dart:io';

import 'package:coriander_player/component/build_index_state_view.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coriander-build-index-');
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  testWidgets('does not run the success callback after an index stream error',
      (tester) async {
    var completed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: BuildIndexStateView(
          indexPath: directory,
          folders: const ['D:/missing'],
          whenIndexBuilt: () => completed++,
          buildIndex: ({required folders, required indexPath}) =>
              Stream<IndexActionState>.error(StateError('scan failed')),
        ),
      ),
    );
    await tester.pump();

    expect(completed, 0);
    expect(find.textContaining('索引创建失败'), findsOneWidget);
  });

  testWidgets('shows an asynchronous completion failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BuildIndexStateView(
          indexPath: directory,
          folders: const ['D:/Music'],
          whenIndexBuilt: () async {
            throw StateError('reload failed');
          },
          buildIndex: ({required folders, required indexPath}) =>
              const Stream<IndexActionState>.empty(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('reload failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
