import 'dart:io';

import 'package:coriander_player/page/welcoming_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requires a folder before the first library scan',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FolderSelectorView(
          applicationSupportDirectory: Future.value(Directory.systemTemp),
        ),
      ),
    );
    await tester.pump();

    final scanButton = tester.widget<FilledButton>(
      find.byKey(const Key('first-library-scan-button')),
    );
    expect(scanButton.onPressed, isNull);
    expect(find.byKey(const Key('first-library-folder-hint')), findsOneWidget);
  });
}
