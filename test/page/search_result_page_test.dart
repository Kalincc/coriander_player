import 'dart:async';
import 'dart:typed_data';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/page/search_page/local_search_controller.dart';
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

  testWidgets('submitting a query with Enter only refreshes local results',
      (tester) async {
    final song = _audio(title: 'Needle Song');
    AudioLibrary.instance.audioCollection.add(song);
    AudioLibrary.instance.artistCollection['Test Artist'] =
        Artist(name: 'Test Artist');
    final index = _index(
      fingerprint: 1,
      lines: const [LyricSearchLine(startMs: 1000, text: 'a needle line')],
    );
    await index.sync([song]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResultPage(
            initialQuery: 'missing',
            lyricIndex: index,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('a needle line', findRichText: true), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows loading first and publishes search categories in batches',
      (tester) async {
    final song = _audio(title: 'needle song', path: 'needle.flac');
    AudioLibrary.instance.audioCollection.add(song);
    AudioLibrary.instance.artistCollection['Test Artist'] =
        Artist(name: 'Test Artist')..works.add(song);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResultPage(
            initialQuery: 'needle',
            lyricIndex: _index(fingerprint: 1, lines: const []),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('needle song'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('drops results from an older search generation', () async {
    final firstSong = _audio(title: 'first song', path: 'first.flac');
    final latestSong = _audio(title: 'latest song', path: 'latest.flac');
    AudioLibrary.instance.audioCollection.addAll([firstSong, latestSong]);
    final firstBatchGate = Completer<void>();
    var yields = 0;
    final controller = LocalSearchController(
      lyricIndex: _index(fingerprint: 1, lines: const []),
      yieldToEventLoop: () {
        yields++;
        return yields == 1 ? firstBatchGate.future : Future<void>.value();
      },
    );
    addTearDown(controller.dispose);

    final firstSearch = controller.search('first');
    expect(controller.value.result.audios, isEmpty);
    expect(controller.value.isLoading, isTrue);

    final latestSearch = controller.search('latest');
    await latestSearch;

    expect(controller.value.result.audios, [same(latestSong)]);
    firstBatchGate.complete();
    await firstSearch;

    expect(controller.value.result.audios, [same(latestSong)]);
    expect(controller.value.isComplete, isTrue);
  });

  test('publishes one search category per yielded batch', () async {
    final song = _audio(title: 'needle song', path: 'needle.flac');
    AudioLibrary.instance.audioCollection.add(song);
    final artist = Artist(name: 'needle artist');
    AudioLibrary.instance.artistCollection[artist.name] = artist;
    final gates = [
      for (var i = 0; i < 4; i++) Completer<void>(),
    ];
    var batch = 0;
    final controller = LocalSearchController(
      lyricIndex: _index(fingerprint: 1, lines: const []),
      yieldToEventLoop: () => gates[batch++].future,
    );
    addTearDown(controller.dispose);

    final searching = controller.search('needle');
    expect(controller.value.result.audios, isEmpty);

    gates[0].complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.result.audios, [same(song)]);
    expect(controller.value.result.artists, isEmpty);

    gates[1].complete();
    gates[2].complete();
    gates[3].complete();
    await searching;

    expect(controller.value.result.artists, [same(artist)]);
    expect(controller.value.isComplete, isTrue);
  });

  test('publishes lyric batches and cancels an older lyric search', () async {
    final songs = [
      for (var i = 0; i < 26; i++)
        _audio(title: 'song $i', path: '$i.flac', modified: i + 1),
    ];
    AudioLibrary.instance.audioCollection.addAll(songs);
    final index = _index(fingerprint: 1, lines: const []);
    for (var i = 0; i < songs.length; i++) {
      index.entries[songs[i].path] = LyricIndexEntry(
        audioPath: songs[i].path,
        fingerprint: LyricFileFingerprint(audioModified: songs[i].modified),
        lines: [
          LyricSearchLine(
            startMs: i * 1000,
            text: i < 25 ? 'older lyric' : 'newer lyric',
          ),
        ],
      );
    }

    final secondLyricBatch = Completer<void>();
    final releaseOlderSearch = Completer<void>();
    var yields = 0;
    final controller = LocalSearchController(
      lyricIndex: index,
      yieldToEventLoop: () {
        yields++;
        if (yields == 6) {
          secondLyricBatch.complete();
          return releaseOlderSearch.future;
        }
        return Future<void>.value();
      },
    );
    addTearDown(controller.dispose);

    final olderSearch = controller.search('older');
    final reachedSecondLyricBatch = await Future.any<bool>([
      secondLyricBatch.future.then((_) => true),
      Future<bool>.delayed(
        const Duration(milliseconds: 100),
        () => false,
      ),
    ]);
    expect(reachedSecondLyricBatch, isTrue);
    if (!reachedSecondLyricBatch) return;

    expect(controller.value.result.lyrics, hasLength(25));
    expect(controller.value.isLoading, isTrue);

    await controller.search('newer');
    expect(controller.value.result.lyrics, hasLength(1));
    expect(controller.value.result.lyrics.single.audio, same(songs.last));

    releaseOlderSearch.complete();
    await olderSearch;

    expect(controller.value.result.lyrics, hasLength(1));
    expect(controller.value.result.lyrics.single.audio, same(songs.last));
  });

  testWidgets('defers lyric refresh until index sync completes',
      (tester) async {
    final songs = [
      for (var i = 0; i < 26; i++)
        _audio(title: 'song $i', path: '$i.flac', modified: i + 1),
    ];
    AudioLibrary.instance.audioCollection.addAll(songs);
    final checkpointReached = Completer<void>();
    final releaseSync = Completer<void>();
    var lyricReads = 0;
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async =>
          LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async {
        lyricReads++;
        if (lyricReads == 26) {
          checkpointReached.complete();
          await releaseSync.future;
        }
        return const [
          LyricSearchLine(startMs: 1000, text: 'needle checkpoint'),
        ];
      },
      workerCount: 1,
    );
    index.entries[songs.first.path] = LyricIndexEntry(
      audioPath: songs.first.path,
      fingerprint: const LyricFileFingerprint(audioModified: 0),
      lines: const [
        LyricSearchLine(startMs: 0, text: 'needle before indexing'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResultPage(initialQuery: 'needle', lyricIndex: index),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final syncing = index.sync(songs);
    await checkpointReached.future;
    await tester.pump();

    expect(index.progress.isSyncing, isTrue);
    expect(index.progress.processed, 25);
    expect(find.text('正在建立本地歌词索引：已处理 25/26'), findsOneWidget);
    expect(find.text('needle checkpoint', findRichText: true), findsNothing);

    releaseSync.complete();
    await syncing;
    await tester.pumpAndSettle();

    expect(find.text('needle checkpoint', findRichText: true), findsWidgets);
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
      AudioLibrary.instance.artistCollection['Test Artist'] =
          Artist(name: 'Test Artist');
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(find.text('updated after refresh', findRichText: true),
          findsOneWidget);
      expect(
          find.text('needle before refresh', findRichText: true), findsNothing);
    },
  );
}

Audio _audio({
  required String title,
  String path = 'test.flac',
  int modified = 100,
}) =>
    Audio(
      title,
      'Test Artist',
      'Test Album',
      1,
      180,
      320,
      44100,
      path,
      modified,
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
