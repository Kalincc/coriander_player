import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_grouped_view.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final view in ContentView.values) {
    testWidgets('first frame stays lazy with 1000 artist groups: $view',
        (tester) async {
      final groups = List.generate(
          1000,
          (index) => AlbumArtistGroup(
                artist: Artist(name: 'Artist $index'),
                albums: [Album(name: 'Album $index')],
              ));
      var built = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AlbumGroupedView(
        groups: groups,
        contentView: view,
        itemBuilder: (_, album) {
          built++;
          return Text(album.name);
        },
      ))));
      expect(built, lessThan(40));
      debugPrint('PERF grouped $view: first-frame albums=$built (1000 groups)');
      await tester.scrollUntilVisible(find.text('Album 20'), 500,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Artist 20 · 1 张专辑'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders headings and albums in a single lazy list',
      (tester) async {
    final shared = Album(name: 'Shared');
    final first = Album(name: 'First');
    final groups = [
      AlbumArtistGroup(
        artist: Artist(name: 'Artist A'),
        albums: [first, shared],
      ),
      AlbumArtistGroup(
        artist: Artist(name: 'Artist B'),
        albums: [shared],
      ),
    ];
    var tapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumGroupedView(
            groups: groups,
            contentView: ContentView.list,
            itemBuilder: (context, album) => InkWell(
              onTap: () => tapped++,
              child: Text(album.name),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Artist A · 2 张专辑'), findsOneWidget);
    expect(find.text('Artist B · 1 张专辑'), findsOneWidget);
    expect(find.text('Shared'), findsNWidgets(2));
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverList), findsOneWidget);

    await tester.tap(find.text('First'));
    expect(tapped, 1);
  });

  testWidgets('table rows retain grid geometry and adapt on resize',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumGroupedView(
            groups: [
              AlbumArtistGroup(
                artist: Artist(name: 'Artist'),
                albums: List.generate(5, (i) => Album(name: 'Album $i')),
              ),
            ],
            contentView: ContentView.table,
            itemBuilder: (context, album) => Text(album.name),
          ),
        ),
      ),
    );

    expect(find.byType(SliverList), findsOneWidget);
    expect(tester.getTopLeft(find.text('Album 0')).dy,
        tester.getTopLeft(find.text('Album 2')).dy);
    expect(
        tester.getTopLeft(find.text('Album 3')).dy -
            tester.getTopLeft(find.text('Album 0')).dy,
        72);
    expect(tester.getTopLeft(find.text('Album 3')).dx,
        tester.getTopLeft(find.text('Album 0')).dx);
    tester.view.physicalSize = const Size(400, 600);
    await tester.pump();
    expect(
        tester.getTopLeft(find.text('Album 2')).dy -
            tester.getTopLeft(find.text('Album 0')).dy,
        72);
  });
}
