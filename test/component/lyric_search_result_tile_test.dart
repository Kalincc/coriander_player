import 'dart:typed_data';

import 'package:coriander_player/component/lyric_search_result_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  testWidgets('renders every matching line and highlights every query match',
      (tester) async {
    await _pumpTile(tester, onLocate: () {});

    expect(find.text('Needle Song'), findsOneWidget);
    expect(find.text('Test Artist - Test Album'), findsOneWidget);
    expect(find.text('first NEEDLE line', findRichText: true), findsOneWidget);
    expect(find.text('another needle', findRichText: true), findsOneWidget);
    expect(find.text('final Needle', findRichText: true), findsOneWidget);
    expect(find.text('2:05'), findsOneWidget);
    expect(
      _highlightedText(tester),
      containsAll(<String>['NEEDLE', 'needle', 'Needle']),
    );
  });

  for (final interaction in <String, Finder>{
    'song header': find.text('Needle Song'),
    'lyric row': find.text('another needle', findRichText: true),
    'location button': find.byIcon(Symbols.location_on),
  }.entries) {
    testWidgets('${interaction.key} invokes locate once', (tester) async {
      var locateCount = 0;
      await _pumpTile(tester, onLocate: () => locateCount++);

      await tester.tap(interaction.value);
      await tester.pump();

      expect(locateCount, 1);
    });
  }
}

Future<void> _pumpTile(
  WidgetTester tester, {
  required VoidCallback onLocate,
}) async {
  final match = LyricSearchMatch(
    audio: Audio(
      'Needle Song',
      'Test Artist',
      'Test Album',
      1,
      180,
      320,
      44100,
      'test.flac',
      100,
      90,
      'test',
    ),
    lines: const [
      LyricSearchLine(startMs: 1000, text: 'first NEEDLE line'),
      LyricSearchLine(startMs: 125000, text: 'another needle'),
      LyricSearchLine(startMs: 126000, text: 'final Needle'),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LyricSearchResultTile(
          match: match,
          query: 'needle',
          onLocate: onLocate,
        ),
      ),
    ),
  );
  await tester.pump();
}

List<String> _highlightedText(WidgetTester tester) {
  final highlighted = <String>[];
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.fontWeight == FontWeight.w600 &&
          span.text != null) {
        highlighted.add(span.text!);
      }
      return true;
    });
  }
  return highlighted;
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
    if (invocation.memberName == #crateApiTagReaderGetPictureFromPath) {
      return Future<Uint8List?>.value();
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
