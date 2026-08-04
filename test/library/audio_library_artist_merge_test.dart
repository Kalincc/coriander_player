import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio testAudio({
  required String artist,
  required String album,
  String title = 'Song',
}) =>
    Audio(
      title,
      artist,
      album,
      1,
      180,
      320,
      44100,
      '$title.flac',
      100,
      90,
      'Lofty',
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('merges Traditional and Simplified artist names into one collection',
      () {
    final library = AudioLibrary.forTesting([
      testAudio(artist: '張學友', album: 'Traditional Album'),
      testAudio(artist: '张学友', album: 'Simplified Album'),
    ]);

    expect(library.artistCollection.keys, ['张学友']);
    final artist = library.artistForName('張學友');
    expect(artist, same(library.artistForName('张学友')));
    expect(artist!.name, '张学友');
    expect(artist.works, hasLength(2));
    expect(
        library.albumCollection['Traditional Album']!.artistsMap.keys, ['张学友']);
  });

  test('keeps non-Chinese artist names distinct', () {
    final library = AudioLibrary.forTesting([
      testAudio(artist: '張學友', album: 'Chinese Album'),
      testAudio(artist: 'YOASOBI', album: 'English Album'),
    ]);

    expect(library.artistCollection.keys, ['张学友', 'YOASOBI']);
    expect(library.artistForName('YOASOBI')!.works, hasLength(1));
  });

  test('deduplicates canonical artist relationships within one audio', () {
    final audio = testAudio(
      artist: '張學友/张学友',
      album: 'Collision Album',
    );
    final library = AudioLibrary.forTesting([audio]);

    expect(audio.artist, '張學友/张学友');
    expect(audio.splitedArtists, ['張學友', '张学友']);
    expect(library.artistCollection.keys, ['张学友']);
    expect(library.artistCollection['张学友']!.works, [same(audio)]);
    expect(
      library.albumCollection['Collision Album']!.artistsMap.keys,
      ['张学友'],
    );
    expect(
      library.artistsForAudio(audio).map((artist) => artist.name),
      ['张学友'],
    );
  });

  test('rebuilding collections does not duplicate relationships', () {
    final library = AudioLibrary.forTesting([
      testAudio(artist: '張學友', album: 'Album'),
      testAudio(artist: '张学友', album: 'Album', title: 'Second Song'),
    ]);

    library.rebuildCollections();

    expect(library.audioCollection, hasLength(2));
    expect(library.artistCollection['张学友']!.works, hasLength(2));
    expect(library.artistCollection['张学友']!.albumsMap, hasLength(1));
    expect(library.albumCollection['Album']!.artistsMap, hasLength(1));
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
    throw UnimplementedError(invocation.memberName.toString());
  }
}
