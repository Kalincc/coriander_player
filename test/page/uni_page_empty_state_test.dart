import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty state replaces the body only while content is empty',
      (tester) async {
    Widget buildPage(List<String> content) => MaterialApp(
          home: UniPage<String>(
            pref: PagePreference(
              0,
              SortOrder.ascending,
              ContentView.list,
            ),
            title: '专辑',
            contentList: content,
            contentBuilder: (context, item, index, controller) => Text(item),
            enableShufflePlay: false,
            enableSortMethod: false,
            enableSortOrder: false,
            enableContentViewSwitch: false,
            emptyState: const Center(child: Text('没有专辑')),
          ),
        );

    await tester.pumpWidget(buildPage(const []));
    expect(find.text('没有专辑'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(GridView), findsNothing);

    await tester.pumpWidget(buildPage(const ['Album A']));
    await tester.pump();
    expect(find.text('Album A'), findsOneWidget);
    expect(find.text('没有专辑'), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });
}
