import 'package:coriander_player/page/now_playing_page/component/lyric_scroll_positioner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'centers the current tile for initial positioning and lyric changes',
    (tester) async {
      final currentTileKey = GlobalKey();
      final currentLine = ValueNotifier(0);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: ValueListenableBuilder<int>(
                valueListenable: currentLine,
                builder: (context, line, _) => ListView(
                  children: [
                    const SizedBox(height: 400),
                    SizedBox(
                      key: line == 0 ? currentTileKey : null,
                      height: 40,
                    ),
                    const SizedBox(height: 120),
                    SizedBox(
                      key: line == 1 ? currentTileKey : null,
                      height: 120,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await LyricScrollPositioner.center(currentTileKey, animate: false);
      await tester.pump();
      expect(_distanceFromViewportCenter(tester, currentTileKey), lessThan(1));

      currentLine.value = 1;
      await tester.pump();
      await LyricScrollPositioner.center(currentTileKey, animate: false);
      await tester.pump();
      expect(_distanceFromViewportCenter(tester, currentTileKey), lessThan(1));
    },
  );
}

double _distanceFromViewportCenter(WidgetTester tester, GlobalKey targetKey) {
  final viewport = tester.getRect(find.byType(Scrollable).first);
  final target = tester.getRect(find.byKey(targetKey));
  return (target.center.dy - viewport.center.dy).abs();
}
