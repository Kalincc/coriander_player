import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path) => Audio(
      path,
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('keeps a single-song playback context to one song', () {
    final song = _audio('D:/music/song.flac');
    final context = PlaybackPlaylistContext();

    context.play(0, [song]);

    expect(context.items, [song]);
    expect(context.currentIndex, 0);
  });

  test('reorder tracks the exact playing occurrence even with duplicate files',
      () {
    final a = _audio('a');
    final b = _audio('b');
    final c = _audio('c');
    final queue = PlaybackPlaylistContext()..play(2, [a, b, b, c]);
    final playingKey = queue.itemKey(2);
    expect(queue.move(2, 0), isTrue);
    expect(queue.currentIndex, 0);
    expect(queue.itemKey(0), playingKey);
    expect(queue.move(0, 4), isTrue);
    expect(queue.items, [a, b, c, b]);
    expect(queue.itemKey(queue.currentIndex), playingKey);
    expect(queue.undo(), isTrue);
    expect(queue.itemKey(queue.currentIndex), playingKey);
  });

  test('remove and clear keep the current item and undo restores the queue',
      () {
    final songs = [_audio('a'), _audio('b'), _audio('c')];
    final queue = PlaybackPlaylistContext()..play(1, songs);
    expect(queue.remove(1), isFalse);
    expect(queue.remove(0), isTrue);
    expect(queue.currentIndex, 0);
    expect(queue.clearUpcoming(), isTrue);
    expect(queue.items, [songs[1]]);
    expect(queue.undo(), isTrue);
    expect(queue.items, [songs[1], songs[2]]);
    expect(queue.undo(), isTrue);
    expect(queue.items, songs);
    expect(queue.currentIndex, 1);
  });

  test('undo after a track change does not jump to the former playing track',
      () {
    final songs = [_audio('a'), _audio('b'), _audio('c')];
    final queue = PlaybackPlaylistContext()..play(0, songs);
    queue.remove(2);
    queue.selectIndex(1);
    queue.undo();
    expect(queue.items, songs);
    expect(queue.currentIndex, 1);
  });

  test('undo never removes an inserted track that has started playing', () {
    final a = _audio('a');
    final b = _audio('b');
    final added = _audio('next');
    final queue = PlaybackPlaylistContext()..play(0, [a, b]);
    queue.insertNext(added);
    queue.selectIndex(1);
    final key = queue.itemKey(1);
    queue.undo();
    expect(queue.items[queue.currentIndex], same(added));
    expect(queue.itemKey(queue.currentIndex), key);
    expect(queue.items, [a, added, b]);
  });

  test(
      'a new playback context invalidates old undo and invalid edits are no-ops',
      () {
    final songs = [_audio('a'), _audio('b')];
    final queue = PlaybackPlaylistContext()..play(0, songs);
    expect(queue.move(-1, 0), isFalse);
    expect(queue.move(0, 1), isFalse);
    expect(queue.remove(99), isFalse);
    expect(queue.canUndo, isFalse);
    queue.clearUpcoming();
    queue.play(0, [songs[1]]);
    expect(queue.undo(), isFalse);
    expect(queue.items, [songs[1]]);
  });

  test('rescan also refreshes metadata in a removed entry retained for undo',
      () {
    final old = _audio(r'D:\Music\song.flac');
    final current = _audio('other');
    final refreshed = _audio('d:/music/song.flac')..title = 'new';
    final queue = PlaybackPlaylistContext()..play(0, [current, old]);
    queue.remove(1);
    queue.reconcileLibrary(AudioLibrary.forTesting([refreshed]));
    queue.undo();
    expect(queue.items.last, same(refreshed));
    expect(queue.currentIndex, 0);
  });

  test('keeps a complete album playback context', () {
    final album = [
      _audio('D:/music/album-1.flac'),
      _audio('D:/music/album-2.flac'),
    ];
    final context = PlaybackPlaylistContext();

    context.play(1, album);

    expect(context.items, album);
    expect(context.currentIndex, 1);
  });

  test('rescan rebinds queue metadata without changing its order or index', () {
    final old = _audio(r'D:\Music\song.flac');
    final missing = _audio('D:/Music/offline.flac');
    final updated = _audio('d:/music/song.flac')..title = 'Updated title';
    final context = PlaybackPlaylistContext()..play(1, [missing, old, old]);
    context.reconcileLibrary(AudioLibrary.forTesting([updated]));
    expect(context.currentIndex, 1);
    expect(context.items, [same(missing), same(updated), same(updated)]);
  });

  test('initializes only playback history', () async {
    final calls = <String>[];
    final initializer = PlaybackDataInitializer(
      loadHistory: () async => calls.add('history'),
    );

    await initializer.initialize(const <Audio>[]);

    expect(calls, ['history']);
  });

  test('reconciles only history after a library scan', () async {
    final liveHistoryPaths = <String>{'kept', 'deleted'};
    final reconciler = PlaybackDataReconciler(
      reconcileHistory: (_) async => liveHistoryPaths.remove('deleted'),
    );

    await reconciler.reconcile(const <Audio>[]);

    expect(liveHistoryPaths, {'kept'});
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
