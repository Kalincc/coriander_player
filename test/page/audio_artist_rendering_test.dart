import 'dart:typed_data';

import 'package:coriander_player/component/artist_tile.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/audio_detail_page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Audio> originalAudios;
  late Map<String, Artist> originalArtists;
  late Map<String, String> originalAliases;
  late Map<String, Album> originalAlbums;
  late Audio audio;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() {
    final library = AudioLibrary.instance;
    originalAudios = List<Audio>.from(library.audioCollection);
    originalArtists = Map<String, Artist>.from(library.artistCollection);
    originalAliases = Map<String, String>.from(library.artistAliases);
    originalAlbums = Map<String, Album>.from(library.albumCollection);

    audio = Audio(
      'Song',
      '張學友/张学友',
      'Album',
      1,
      180,
      320,
      44100,
      'song.flac',
      100,
      90,
      'test',
    );
    final artist = Artist(name: '张学友')..works.add(audio);
    final album = Album(name: 'Album')
      ..works.add(audio)
      ..artistsMap[artist.name] = artist;
    artist.albumsMap[album.name] = album;

    library.audioCollection
      ..clear()
      ..add(audio);
    library.artistCollection
      ..clear()
      ..[artist.name] = artist;
    library.artistAliases
      ..clear()
      ..['張學友'] = artist.name
      ..['张学友'] = artist.name;
    library.albumCollection
      ..clear()
      ..[album.name] = album;
  });

  tearDown(() {
    final library = AudioLibrary.instance;
    library.audioCollection
      ..clear()
      ..addAll(originalAudios);
    library.artistCollection
      ..clear()
      ..addAll(originalArtists);
    library.artistAliases
      ..clear()
      ..addAll(originalAliases);
    library.albumCollection
      ..clear()
      ..addAll(originalAlbums);
  });

  testWidgets('audio tile menu renders one canonical artist entry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioTile(audioIndex: 0, playlist: [audio]),
        ),
      ),
    );
    await tester.pump();

    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    final artistSubmenu = anchor.menuChildren.first as SubmenuButton;

    expect(artistSubmenu.menuChildren, hasLength(1));
    expect(
      (artistSubmenu.menuChildren.single as MenuItemButton).child,
      isA<Text>().having((text) => text.data, 'label', '张学友'),
    );
  });

  testWidgets('audio detail renders one linkable canonical artist entry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AudioDetailPage(audio: audio)),
    );
    await tester.pump();

    expect(find.byType(ArtistTile), findsOneWidget);
    expect(
      tester.widget<ArtistTile>(find.byType(ArtistTile)).artist.name,
      '张学友',
    );
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
