import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_artist_filter.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('artist search is case-insensitive and results are pinyin-sorted', () {
    final names = ['周杰伦', 'Aimer', '陈奕迅'];

    expect(filterArtistNames(names, ' AI '), ['Aimer']);
    expect(filterArtistNames(names, ''), ['Aimer', '陈奕迅', '周杰伦']);
  });

  test('album derivation filters by artist and falls back for stale names', () {
    final all = [Album(name: 'All 2'), Album(name: 'All 1')];
    final artist = Artist(name: 'Artist')
      ..albumsMap['Only 2'] = Album(name: 'Only 2')
      ..albumsMap['Only 1'] = Album(name: 'Only 1');

    expect(
      albumsForArtist(
        allAlbums: all,
        artists: {'Artist': artist},
        artistName: null,
      ),
      all,
    );
    final filtered = albumsForArtist(
      allAlbums: all,
      artists: {'Artist': artist},
      artistName: 'Artist',
    );
    filtered.sort((a, b) => a.name.localeCompareTo(b.name));
    expect(filtered.map((album) => album.name), ['Only 1', 'Only 2']);
    filtered.sort((a, b) => b.name.localeCompareTo(a.name));
    expect(filtered.map((album) => album.name), ['Only 2', 'Only 1']);
    expect(
      albumsForArtist(
        allAlbums: all,
        artists: const {},
        artistName: 'Removed',
      ),
      all,
    );
    expect(
      AppPreference.instance.albumsPagePref.toMap().keys,
      unorderedEquals(['sortMethod', 'sortOrder', 'contentView']),
    );
  });

  testWidgets('dialog searches, selects an artist, and resets to no category',
      (tester) async {
    String? selected;
    var callbackCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => AlbumArtistFilterButton(
            artistNames: const ['Aimer', '陈奕迅', '周杰伦'],
            selectedArtistName: selected,
            onSelected: (value) => setState(() {
              callbackCount++;
              selected = value;
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('艺术家：无分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(callbackCount, 0);

    await tester.tap(find.text('艺术家：无分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '周');
    await tester.pump();
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.text('陈奕迅'), findsNothing);

    await tester.tap(find.text('周杰伦'));
    await tester.pumpAndSettle();
    expect(find.text('艺术家：周杰伦'), findsOneWidget);
    expect(callbackCount, 1);

    await tester.tap(find.text('艺术家：周杰伦'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无分类'));
    await tester.pumpAndSettle();
    expect(find.text('艺术家：无分类'), findsOneWidget);
    expect(callbackCount, 2);
  });
}
