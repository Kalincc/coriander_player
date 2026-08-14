import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:coriander_player/component/listening_duration_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses listened duration for vertical bars and shows covers',
      (tester) async {
    var tapped = '';
    final items = [
      ListeningDurationChartItem(
        label: 'Long song title',
        listened: const Duration(minutes: 2),
        playCount: 1,
        artwork: Future.value(),
        onTap: () => tapped = 'long',
      ),
      ListeningDurationChartItem(
        label: 'Short',
        listened: const Duration(minutes: 1),
        playCount: 9,
        artwork: Future.value(),
        onTap: () => tapped = 'short',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ListeningDurationChart(items: items),
          ),
        ),
      ),
    );

    expect(find.text('0秒'), findsOneWidget);
    expect(find.text('2分0秒'), findsOneWidget);
    final longBar = tester.widget<SizedBox>(
      find.byKey(const ValueKey('listening-chart-bar-Long song title')),
    );
    final shortBar = tester.widget<SizedBox>(
      find.byKey(const ValueKey('listening-chart-bar-Short')),
    );
    expect(longBar.height, closeTo(168, 0.01));
    expect(shortBar.height, closeTo(84, 0.01));
    expect(find.byType(ArtworkThumbnail), findsNWidgets(2));
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.text('Long song title'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      'Long song title',
    );

    await tester.tap(
      find.byKey(const ValueKey('listening-chart-item-Short')),
    );
    expect(tapped, 'short');
  });

  testWidgets('ten fixed columns scroll horizontally in a narrow viewport',
      (tester) async {
    final items = List.generate(
      10,
      (index) => ListeningDurationChartItem(
        label: 'Song $index',
        listened: Duration(seconds: index + 1),
        playCount: 1,
        artwork: Future.value(),
        onTap: () {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: ListeningDurationChart(items: items),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('listening-chart-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
