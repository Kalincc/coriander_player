import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio makeAudio(String path) => Audio(
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
  late Directory directory;
  late LocalJsonStore store;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() async {
    PLAYLISTS.clear();
    directory = await Directory.systemTemp.createTemp('coriander-playlists-');
    store = LocalJsonStore(directory);
  });

  tearDown(() async {
    PLAYLISTS.clear();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('reads legacy playlists and defaults a missing system marker to false',
      () async {
    final song = makeAudio('D:/music/legacy.flac');
    await store.writeAtomically('playlists.json', [
      {
        'name': '旧歌单',
        'audios': [song.toMap()],
      },
    ]);

    await readPlaylists(store: store);

    final legacy = PLAYLISTS.singleWhere((item) => item.name == '旧歌单');
    expect(legacy.isSystem, isFalse);
    expect(legacy.audios, contains(song.path));
    expect(PLAYLISTS.where((item) => item.name == likedPlaylistName),
        hasLength(1));
  });

  test('merges duplicate liked playlists by path into one protected playlist',
      () async {
    final first = makeAudio('D:/music/first.flac');
    final second = makeAudio('D:/music/second.flac');
    await store.writeAtomically('playlists.json', [
      Playlist(likedPlaylistName, {first.path: first}).toMap(),
      Playlist(likedPlaylistName, {
        first.path: first,
        second.path: second,
      }).toMap(),
    ]);

    await readPlaylists(store: store);
    await readPlaylists(store: store);

    final liked =
        PLAYLISTS.singleWhere((item) => item.name == likedPlaylistName);
    expect(liked.isSystem, isTrue);
    expect(liked.audios.keys, {first.path, second.path});
    expect(PLAYLISTS, hasLength(1));
  });

  test('does not rename or remove the protected liked playlist', () async {
    await ensureLikedPlaylist();
    final liked = PLAYLISTS.single;

    expect(liked.rename('其他名称'), isFalse);
    expect(removePlaylist(liked), isFalse);
    expect(liked.name, likedPlaylistName);
    expect(PLAYLISTS, [same(liked)]);
  });

  test('toggles a song in the liked playlist and persists the change',
      () async {
    final song = makeAudio('D:/music/favorite.flac');

    await toggleLiked(song, store: store);
    expect(isLiked(song), isTrue);

    PLAYLISTS.clear();
    await readPlaylists(store: store);
    expect(isLiked(song), isTrue);

    await toggleLiked(song, store: store);
    expect(isLiked(song), isFalse);
  });

  test('removes deleted songs from every playlist during reconciliation',
      () async {
    final kept = makeAudio('D:/music/kept.flac');
    final deleted = makeAudio('D:/music/deleted.flac');
    PLAYLISTS.add(Playlist('收藏', {
      kept.path: kept,
      deleted.path: deleted,
    }));

    await reconcilePlaylistAudios([kept], store: store);

    expect(PLAYLISTS.single.audios.keys, [kept.path]);
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
