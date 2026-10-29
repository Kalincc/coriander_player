import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/page/search_page/local_search_controller.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('large matching searches publish bounded snapshots, not every 25 songs',
      () async {
    final songs = List.generate(
        10000,
        (index) => Audio('Needle $index', 'Artist', 'Album', 1, 180, 320, 44100,
            '$index.flac', 1, 1, 'test'));
    final library = AudioLibrary.forTesting(songs);
    final controller = LocalSearchController(
      lyricIndex: _emptyLyricIndex(),
      libraryProvider: () => library,
      yieldToEventLoop: () async {},
    );
    addTearDown(controller.dispose);
    var updates = 0;
    var copiedItems = 0;
    controller.addListener(() {
      updates++;
      copiedItems += controller.value.result.audios.length;
    });
    await controller.search('needle');
    expect(controller.value.result.audios, hasLength(10000));
    expect(updates, lessThan(100));
    expect(copiedItems, lessThan(500000));
    debugPrint(
        'PERF 10000 matches: updates=$updates, snapshot-items=$copiedItems');
  });

  test('artist scanning yields in bounded chunks and supports cancellation',
      () async {
    var reads = 0;
    final library = AudioLibrary.forTesting([]);
    for (var i = 0; i < 1000; i++) {
      library.artistCollection['$i'] =
          _CountingArtist('Needle $i', () => reads++);
    }
    final gate = Completer<void>();
    var yields = 0;
    final controller = LocalSearchController(
      lyricIndex: _emptyLyricIndex(),
      libraryProvider: () => library,
      yieldToEventLoop: () =>
          ++yields == 2 ? gate.future : Future<void>.value(),
    );
    addTearDown(controller.dispose);
    final old = controller.search('needle');
    await Future<void>.delayed(Duration.zero);
    expect(reads, 25);
    final latest = controller.search('');
    gate.complete();
    await Future.wait([old, latest]);
    expect(reads, 25);
    expect(controller.value.result.artists, isEmpty);
    expect(controller.value.result.query, '');
    expect(controller.value.isComplete, isTrue);
  });

  test('reads the replaced AudioLibrary singleton on every search', () async {
    final directory =
        await Directory.systemTemp.createTemp('coriander_search_library_');
    addTearDown(() => directory.delete(recursive: true));
    final indexFile =
        File('${directory.path}${Platform.pathSeparator}index.json');

    await _writeIndex(indexFile, title: 'Old Library Song', path: 'old.flac');
    await AudioLibrary.initFromIndex(indexFile: indexFile);
    final oldLibrary = AudioLibrary.instance;
    final oldAudio = oldLibrary.audioCollection.single;
    final controller = LocalSearchController(lyricIndex: _emptyLyricIndex());
    addTearDown(controller.dispose);

    await controller.search('library');
    expect(controller.value.result.audios, [same(oldAudio)]);

    await _writeIndex(indexFile, title: 'New Library Song', path: 'new.flac');
    await AudioLibrary.initFromIndex(indexFile: indexFile);
    final newLibrary = AudioLibrary.instance;
    final newAudio = newLibrary.audioCollection.single;
    expect(newLibrary, isNot(same(oldLibrary)));

    await controller.search('library');

    expect(controller.value.result.audios, [same(newAudio)]);
    expect(controller.value.result.audios, isNot(contains(same(oldAudio))));
  });
}

Future<void> _writeIndex(
  File file, {
  required String title,
  required String path,
}) =>
    file.writeAsString(
      jsonEncode({
        'version': 110,
        'roots': ['D:/Music'],
        'folders': [
          {
            'path': 'D:/Music/Artist/Album',
            'modified': 1,
            'latest': 1,
            'audios': [
              {
                'title': title,
                'artist': 'Artist',
                'album': 'Album',
                'track': 1,
                'duration': 180,
                'bitrate': 320,
                'sample_rate': 44100,
                'path': path,
                'modified': 1,
                'created': 1,
                'by': 'test',
              },
            ],
          },
        ],
      }),
    );

LyricSearchIndex _emptyLyricIndex() => LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (_) async => throw StateError('not used'),
      lyricLinesFor: (_) async => throw StateError('not used'),
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
    throw UnimplementedError(invocation.memberName.toString());
  }
}

class _CountingArtist extends Artist {
  _CountingArtist(String name, this.onRead) : super(name: name);
  final VoidCallback onRead;
  @override
  String get name {
    onRead();
    return super.name;
  }
}
