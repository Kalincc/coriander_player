import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_detail_page.dart';
import 'package:coriander_player/page/artist_detail_page.dart';
import 'package:coriander_player/page/audio_detail_page.dart';
import 'package:coriander_player/page/audios_page.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _song(String title, String artist, String album, {int disc = 1}) => Audio(
    title,
    artist,
    album,
    1,
    180,
    320,
    44100,
    'D:/music/$disc.flac',
    1,
    1,
    'test',
    disc: disc,
    albumArtist: artist);

void main() {
  late Directory directory;
  late File index;
  late Audio old;

  Future<void> load(List<Audio> audios) async {
    await index.writeAsString(jsonEncode({
      'folders': [
        {
          'path': 'D:/music',
          'modified': 1,
          'latest': 1,
          'audios': audios.map((a) => a.toMap()).toList()
        },
      ],
    }));
    await AudioLibrary.initFromIndex(indexFile: index);
  }

  Widget scoped(Widget child) =>
      AudioLibraryScope(child: MaterialApp(home: Scaffold(body: child)));

  setUpAll(() => RustLib.initMock(api: _Api()));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coriander-metadata-');
    index = File('${directory.path}/index.json');
    old = _song('Old song', 'Old artist', 'Old album');
    await load([old]);
  });
  tearDown(() => directory.delete(recursive: true));

  testWidgets('open song list refreshes after a library reload',
      (tester) async {
    await tester.pumpWidget(scoped(const AudiosPage()));
    await tester.pump();
    expect(find.text('Old song'), findsOneWidget);
    await tester
        .runAsync(() => load([_song('New song', 'New artist', 'New album')]));
    await tester.pump();
    expect(find.text('New song'), findsOneWidget);
    expect(find.text('Old song'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open audio detail resolves the latest tags by file path',
      (tester) async {
    await tester.pumpWidget(scoped(AudioDetailPage(audio: old)));
    await tester.pump();
    await tester
        .runAsync(() => load([_song('New song', 'New artist', 'New album')]));
    await tester.pump();
    expect(find.text('New song'), findsOneWidget);
    expect(find.text('New album'), findsOneWidget);
    expect(find.text('Old song'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open album follows renamed tags and shows disc order',
      (tester) async {
    final preference = AppPreference.instance.albumDetailPagePref;
    AppPreference.instance.albumDetailPagePref =
        PagePreference(2, SortOrder.ascending, ContentView.list);
    addTearDown(() => AppPreference.instance.albumDetailPagePref = preference);
    final album = AudioLibrary.instance.albumCollection.values.single;
    await tester.pumpWidget(scoped(AlbumDetailPage(album: album)));
    await tester.pump();
    await tester.runAsync(() => load([
          _song('Disc two', 'New artist', 'New album', disc: 2),
          _song('Disc one', 'New artist', 'New album'),
        ]));
    await tester.pump();
    expect(find.text('New album'), findsOneWidget);
    expect(find.text('CD1 · 01'), findsOneWidget);
    expect(find.text('CD2 · 01'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Disc one')).dy,
        lessThan(tester.getTopLeft(find.text('Disc two')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open artist follows a renamed tag and removed album is safe',
      (tester) async {
    final artist = AudioLibrary.instance.artistCollection.values.single;
    final album = AudioLibrary.instance.albumCollection.values.single;
    await tester.pumpWidget(scoped(ArtistDetailPage(artist: artist)));
    await tester.pump();
    await tester
        .runAsync(() => load([_song('New song', 'New artist', 'New album')]));
    await tester.pump();
    expect(find.text('New artist'), findsOneWidget);
    expect(find.text('New song'), findsOneWidget);
    await tester.runAsync(() => load([]));
    await tester.pumpWidget(scoped(AlbumDetailPage(album: album)));
    await tester.pump();
    expect(find.text('该专辑已不在音乐库中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Api implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    if (invocation.memberName == #crateApiTagReaderGetPictureFromPath) {
      return Future<Uint8List?>.value();
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
