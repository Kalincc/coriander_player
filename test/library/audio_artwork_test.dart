import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.reads = 0;
    api.picture = Completer<Uint8List?>()..complete(null);
  });

  test('concurrent and missing-artwork requests share a single read', () async {
    api.picture = Completer<Uint8List?>();
    final audio = Audio('Title', 'Artist', 'Album', 1, 180, 320, 44100,
        'D:/music/cover-single-flight.flac', 1, 1, 'test');
    final pending = [for (var i = 0; i < 20; i++) audio.cover];
    await Future<void>.delayed(Duration.zero);
    expect(api.reads, 1);
    api.picture.complete(null);
    expect(await Future.wait(pending), everyElement(isNull));
    expect(await audio.cover, isNull);
    expect(api.reads, 1);
  });

  test(
      'reloading an index invalidates a cached miss even with unchanged timestamps',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander-artwork-');
    addTearDown(() => directory.delete(recursive: true));
    final audio = Audio('Title', 'Artist', 'Album', 1, 180, 320, 44100,
        'D:/music/cover-rescan.flac', 1, 1, 'test');
    final index = File('${directory.path}/index.json');
    await index.writeAsString(jsonEncode({
      'folders': [
        {
          'path': 'D:/music',
          'modified': 1,
          'latest': 1,
          'audios': [audio.toMap()]
        },
      ]
    }));
    expect(await audio.cover, isNull);
    expect(api.reads, 1);
    await AudioLibrary.initFromIndex(indexFile: index);
    expect(await AudioLibrary.instance.audioCollection.single.cover, isNull);
    expect(api.reads, 2);
  });
}

class _Api implements RustLibApi {
  int reads = 0;
  var picture = Completer<Uint8List?>();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    if (invocation.memberName == #crateApiTagReaderGetPictureFromPath) {
      reads++;
      return picture.future;
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
