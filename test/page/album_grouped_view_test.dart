import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_grouped_view.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.byType(SliverFixedExtentList), findsNWidgets(2));

    await tester.tap(find.text('First'));
    expect(tapped, 1);
  });

  testWidgets('uses sliver grids for table view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumGroupedView(
            groups: [
              AlbumArtistGroup(
                artist: Artist(name: 'Artist'),
                albums: [Album(name: 'Album')],
              ),
            ],
            contentView: ContentView.table,
            itemBuilder: (context, album) => Text(album.name),
          ),
        ),
      ),
    );

    expect(find.byType(SliverGrid), findsOneWidget);
  });
}
