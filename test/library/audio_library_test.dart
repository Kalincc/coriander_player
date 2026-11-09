import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('loads configured scan roots without deriving them from folders',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_audio_library_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'roots': ['D:/Music', 'E:/Archive'],
      'folders': [
        _folder('D:/Music/Artist/Album', 'D:/Music/Artist/Album/song.flac'),
      ],
    }));

    await AudioLibrary.initFromIndex(indexFile: indexFile);

    expect(AudioLibrary.instance.scanRoots, ['D:/Music', 'E:/Archive']);
    expect(AudioLibrary.instance.audioCollection.single.path,
        'D:/Music/Artist/Album/song.flac');
  });

  test('keeps a legacy index playable but leaves scan roots empty', () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_legacy_library_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'folders': [
        _folder('D:/Music/Artist/Album', 'D:/Music/Artist/Album/song.flac'),
      ],
    }));

    await AudioLibrary.initFromIndex(indexFile: indexFile);

    expect(AudioLibrary.instance.scanRoots, isEmpty);
    expect(AudioLibrary.instance.audioCollection.single.path,
        'D:/Music/Artist/Album/song.flac');
  });

  test('background index build uses the current artist separator', () async {
    final settings = AppSettings.instance;
    final previous = settings.artistSplitPattern;
    settings.artistSplitPattern = ';';
    addTearDown(() => settings.artistSplitPattern = previous);
    final directory = await Directory.systemTemp.createTemp('coriander-split-');
    addTearDown(() => directory.delete(recursive: true));
    final index = File('${directory.path}/index.json');
    final folder = _folder('D:/Music', 'D:/Music/song.flac');
    final song = (folder['audios'] as List).single as Map;
    song['artist'] = '甲;乙';
    song['album_artist'] = '專輯甲;專輯乙';
    await index.writeAsString(jsonEncode({
      'folders': [folder]
    }));

    await AudioLibrary.initFromIndex(indexFile: index);
    final library = AudioLibrary.instance;
    final audio = library.audioCollection.single;
    final album = library.albumCollection.values.single;
    expect(audio.splitedArtists, ['甲', '乙']);
    expect(album.albumArtistNames, {'专辑甲', '专辑乙'});
    expect(album.artistsMap.keys, ['甲', '乙']);
    expect(library.artistCollection['专辑乙']!.albumsMap[album.id], same(album));
    expect(library.albumForAudio(audio), same(album));
  });

  test('surfaces a corrupt index without replacing the loaded library',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_corrupt_library_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'roots': ['D:/Music'],
      'folders': [
        _folder('D:/Music/Artist/Album', 'D:/Music/Artist/Album/kept.flac'),
      ],
    }));
    await AudioLibrary.initFromIndex(indexFile: indexFile);
    await indexFile.writeAsString('{broken');

    await expectLater(
      AudioLibrary.initFromIndex(indexFile: indexFile),
      throwsFormatException,
    );

    expect(AudioLibrary.instance.audioCollection.single.path,
        'D:/Music/Artist/Album/kept.flac');
  });

  test('rejects malformed root entries without replacing the loaded library',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_invalid_roots_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'roots': ['D:/Music'],
      'folders': [
        _folder('D:/Music/Artist/Album', 'D:/Music/Artist/Album/kept.flac'),
      ],
    }));
    await AudioLibrary.initFromIndex(indexFile: indexFile);
    await indexFile.writeAsString(jsonEncode({
      'version': 110,
      'roots': ['E:/Archive', 42],
      'folders': <Object>[],
    }));

    await expectLater(
      AudioLibrary.initFromIndex(indexFile: indexFile),
      throwsFormatException,
    );

    expect(AudioLibrary.instance.scanRoots, ['D:/Music']);
    expect(AudioLibrary.instance.audioCollection.single.path,
        'D:/Music/Artist/Album/kept.flac');
  });
}

Map<String, Object> _folder(String path, String audioPath) => {
      'path': path,
      'modified': 1,
      'latest': 1,
      'audios': [
        {
          'title': 'Song',
          'artist': 'Artist',
          'album': 'Album',
          'track': 1,
          'duration': 180,
          'bitrate': 320,
          'sample_rate': 44100,
          'path': audioPath,
          'modified': 1,
          'created': 1,
          'by': 'Lofty',
        },
      ],
    };

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
