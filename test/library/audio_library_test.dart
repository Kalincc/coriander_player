import 'dart:convert';
import 'dart:io';

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
