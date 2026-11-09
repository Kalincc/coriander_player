import 'dart:typed_data';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/albums_page.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Audio _audio(String title, String artist, String album) => Audio(
      title,
      artist,
      album,
      1,
      180,
      320,
      44100,
      '$title.flac',
      0,
      0,
      'test',
    );

void main() {
  late Map<String, Artist> originalArtists;
  late Map<String, Album> originalAlbums;
  late PagePreference originalPreference;
  late bool originalCoverWall;

  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));

  setUp(() {
    final library = AudioLibrary.instance;
    originalArtists = Map.of(library.artistCollection);
    originalAlbums = Map.of(library.albumCollection);
    originalPreference = AppPreference.instance.albumsPagePref;
    originalCoverWall = AppPreference.instance.albumCoverWall;
    AppPreference.instance.albumCoverWall = false;
    AppPreference.instance.albumsPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.list);

    final alpha = Album(name: 'Alpha')
      ..works.add(_audio('A', 'Artist A', 'Alpha'));
    final zulu = Album(name: 'Zulu')
      ..works.addAll([
        _audio('Z1', 'Artist A', 'Zulu'),
        _audio('Z2', 'Artist A', 'Zulu'),
      ]);
    final solo = Album(name: 'Solo')
      ..works.add(_audio('S', 'Artist B', 'Solo'));
    final artistA = Artist(name: 'Artist A')
      ..albumsMap.addAll({'Alpha': alpha, 'Zulu': zulu});
    final artistB = Artist(name: 'Artist B')..albumsMap['Solo'] = solo;
    alpha.artistsMap['Artist A'] = artistA;
    zulu.artistsMap['Artist A'] = artistA;
    solo.artistsMap['Artist B'] = artistB;
    library.artistCollection
      ..clear()
      ..addAll({'Artist A': artistA, 'Artist B': artistB});
    library.albumCollection
      ..clear()
      ..addAll({'Alpha': alpha, 'Zulu': zulu, 'Solo': solo});
  });

  tearDown(() {
    AudioLibrary.instance.artistCollection
      ..clear()
      ..addAll(originalArtists);
    AudioLibrary.instance.albumCollection
      ..clear()
      ..addAll(originalAlbums);
    AppPreference.instance.albumsPagePref = originalPreference;
    AppPreference.instance.albumCoverWall = originalCoverWall;
  });

  testWidgets('defaults to artist groups and sorts only inside each group',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pump();

    expect(find.text('分类：按艺术家'), findsOneWidget);
    expect(find.text('Artist A · 2 张专辑'), findsOneWidget);
    expect(find.text('Artist B · 1 张专辑'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Artist A · 2 张专辑')).dy,
        lessThan(tester.getTopLeft(find.text('Artist B · 1 张专辑')).dy));
    expect(tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zulu')).dy));

    await tester.tap(find.byTooltip('切换排序顺序；现在：升序'));
    await tester.pump();

    expect(tester.getTopLeft(find.text('Zulu')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy));
    expect(tester.getTopLeft(find.text('Artist A · 2 张专辑')).dy,
        lessThan(tester.getTopLeft(find.text('Artist B · 1 张专辑')).dy));
  });

  testWidgets('can switch to uncategorized and one artist', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pump();

    await tester.tap(find.text('分类：按艺术家'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类：无分类'));
    await tester.pumpAndSettle();
    expect(find.text('Artist A · 2 张专辑'), findsNothing);
    expect(find.text('3 张专辑'), findsOneWidget);

    await tester.tap(find.text('分类：无分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist B'));
    await tester.pumpAndSettle();
    expect(find.text('艺术家：Artist B'), findsOneWidget);
    expect(find.text('该艺术家的 1 张专辑'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('large square covers retain group order, filtering and details',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AlbumsPage()),
      GoRoute(
        path: app_paths.ALBUM_DETAIL_PAGE,
        builder: (_, state) => Scaffold(
          body: Text('Opened ${(state.extra! as Album).name}'),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换专辑视图；现在：列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('封面墙'));
    await tester.pumpAndSettle();

    expect(AppPreference.instance.albumCoverWall, isTrue);
    expect(find.text('Artist A · 2 张专辑'), findsOneWidget);
    final cover = tester.getSize(find.byType(ArtworkThumbnail).first);
    expect(cover.width, greaterThan(120));
    expect(cover.width, closeTo(cover.height, 0.01));
    expect(tester.getTopLeft(find.text('Alpha')).dx,
        lessThan(tester.getTopLeft(find.text('Zulu')).dx));
    await tester.tap(find.byTooltip('切换排序顺序；现在：升序'));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Zulu')).dx,
        lessThan(tester.getTopLeft(find.text('Alpha')).dx));

    await tester.tap(find.text('分类：按艺术家'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist B'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkThumbnail), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await tester.tap(find.byType(ArtworkThumbnail));
    await tester.pumpAndSettle();
    expect(find.text('Opened Solo'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换专辑视图；现在：封面墙'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(AppPreference.instance.albumCoverWall, isFalse);
    expect(find.byType(ArtworkThumbnail), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
