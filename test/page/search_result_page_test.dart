import 'dart:typed_data';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:coriander_player/page/search_page/search_result_page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Audio> originalAudios;
  late Map<String, Artist> originalArtists;
  late Map<String, Album> originalAlbums;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() {
    final library = AudioLibrary.instance;
    originalAudios = List<Audio>.from(library.audioCollection);
    originalArtists = Map<String, Artist>.from(library.artistCollection);
    originalAlbums = Map<String, Album>.from(library.albumCollection);
    library.audioCollection.clear();
    library.artistCollection.clear();
    library.albumCollection.clear();
  });

  tearDown(() {
    final library = AudioLibrary.instance;
    library.audioCollection
      ..clear()
      ..addAll(originalAudios);
    library.artistCollection
      ..clear()
      ..addAll(originalArtists);
    library.albumCollection
      ..clear()
      ..addAll(originalAlbums);
  });

  test('union search combines title and grouped lyric matches', () async {
    final song = _audio(title: 'Needle Song');
    AudioLibrary.instance.audioCollection.add(song);
    final index = _index(
      fingerprint: 1,
      lines: const [LyricSearchLine(startMs: 1000, text: 'a needle line')],
    );
    await index.sync([song]);

    final result = UnionSearchResult.search('needle', lyricIndex: index);

    expect(result.audios, [same(song)]);
    expect(result.lyrics, hasLength(1));
    expect(result.lyrics.single.audio, same(song));
    expect(result.lyrics.single.lines.single.text, 'a needle line');
  });

  test('union search finds the canonical artist for both Chinese variants', () {
    final artist = Artist(name: '张学友');
    AudioLibrary.instance.artistCollection[artist.name] = artist;

    expect(
      UnionSearchResult.search('張學友').artists,
      contains(same(artist)),
    );
    expect(
      UnionSearchResult.search('张学友').artists,
      contains(same(artist)),
    );
  });

  testWidgets(
    'shows five ordered tabs and refreshes the current query after index sync',
    (tester) async {
      final song = _audio(title: 'Needle Song');
      AudioLibrary.instance.audioCollection.add(song);
      var fingerprint = 1;
      var lines = const [
        LyricSearchLine(startMs: 1000, text: 'needle before refresh'),
      ];
      final index = LyricSearchIndex(
        readIndex: () async => null,
        writeIndex: (_) async {},
        fingerprintFor: (_) async =>
            LyricFileFingerprint(audioModified: fingerprint),
        lyricLinesFor: (_) async => lines,
        workerCount: 1,
      );
      await index.sync([song]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultPage(
              initialQuery: 'needle',
              lyricIndex: index,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widgetList<Tab>(find.byType(Tab)).map((tab) => tab.text),
        ['所有', '音乐', '歌词', '艺术家', '专辑'],
      );
      expect(find.text('needle before refresh', findRichText: true),
          findsOneWidget);

      await tester.enterText(find.byType(TextField), 'updated');
      fingerprint = 2;
      lines = const [
        LyricSearchLine(startMs: 2000, text: 'updated after refresh'),
      ];
      await index.sync([song]);
      await tester.pump();

      expect(find.text('updated after refresh', findRichText: true),
          findsOneWidget);
      expect(
          find.text('needle before refresh', findRichText: true), findsNothing);
    },
  );
}

Audio _audio({required String title}) => Audio(
      title,
      'Test Artist',
      'Test Album',
      1,
      180,
      320,
      44100,
      'test.flac',
      100,
      90,
      'test',
    );

LyricSearchIndex _index({
  required int fingerprint,
  required List<LyricSearchLine> lines,
}) =>
    LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (_) async =>
          LyricFileFingerprint(audioModified: fingerprint),
      lyricLinesFor: (_) async => lines,
      workerCount: 1,
    );

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
