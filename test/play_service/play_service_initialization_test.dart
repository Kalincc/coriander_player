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
