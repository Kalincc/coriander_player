import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_scroll_positioner.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('a line change replaces only two rows and retains click targets',
      (tester) async {
    final lyric = Lrc([
      for (var i = 0; i < 100; i++)
        LrcLine(Duration(seconds: i), 'line $i', isBlank: false),
    ], LrcSource.local);
    final currentKey = GlobalKey();
    var tapped = -1;
    Widget view(int line, Lrc content) => MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider(
              create: (_) => LyricViewController(),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 300),
                    LyricTileList(
                      lyric: content,
                      currentLine: line,
                      currentTileKey: currentKey,
                      onTap: (index) => tapped = index,
                    ),
                    const SizedBox(height: 300),
                  ],
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(view(0, lyric));
    final before =
        tester.widgetList<LyricViewTile>(find.byType(LyricViewTile)).toList();
    await tester.pumpWidget(view(2, lyric));
    final after =
        tester.widgetList<LyricViewTile>(find.byType(LyricViewTile)).toList();
    expect(
        [for (var i = 0; i < 100; i++) identical(before[i], after[i])]
            .where((same) => !same),
        hasLength(2));
    expect(after[0].opacity, .18);
    expect(after[2].opacity, 1);
    expect(after[2].key, currentKey);
    await tester.tap(find.text('line 1'));
    expect(tapped, 1);
    await tester.pumpWidget(view(80, lyric));
    await LyricScrollPositioner.center(currentKey, animate: false);
    await tester.pump();
    final viewport = tester.getRect(find.byType(Scrollable));
    expect(
        (tester.getRect(find.byKey(currentKey)).center.dy - viewport.center.dy)
            .abs(),
        lessThan(1));
    await tester.pumpWidget(view(
        0,
        Lrc([
          LrcLine(Duration.zero, 'replacement', isBlank: false),
        ], LrcSource.local)));
    expect(find.byType(LyricViewTile), findsOneWidget);
    expect(find.text('replacement'), findsOneWidget);
  });
}
