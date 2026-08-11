import 'dart:typed_data';

import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder appIcon() => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'app_icon.ico',
      );

  testWidgets('uses the app icon when the artwork future is absent',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ArtworkThumbnail(image: null, size: 48),
      ),
    );

    expect(appIcon(), findsOneWidget);
  });

  testWidgets('uses the app icon when artwork is unavailable or fails',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkThumbnail(image: Future.value(null), size: 48),
      ),
    );
    await tester.pump();
    expect(appIcon(), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkThumbnail(
          image: Future.value(MemoryImage(Uint8List(0))),
          size: 48,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(appIcon(), findsOneWidget);
  });
}
