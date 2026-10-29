import 'dart:async';
import 'dart:convert';
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

  test('recovers schema-invalid primary from a legacy backup before migrating',
      () async {
    final song = makeAudio('D:/music/recovered.flac');
    final primary = File('${directory.path}/playlists.json');
    final backup = File('${primary.path}.bak');
    await primary.writeAsString('{"version":1,"playlists":"broken"}');
    await backup.writeAsString(jsonEncode([
      {
        'name': '恢复歌单',
        'audios': [song.toMap()],
      },
    ]));

    await readPlaylists(store: store);

    expect(PLAYLISTS.first.name, '恢复歌单');
    expect(PLAYLISTS.first.audios.keys, [song.path]);
    expect(jsonDecode(await primary.readAsString())['version'], 1);
    final savedBackup = jsonDecode(await backup.readAsString()) as List;
    expect(savedBackup.single['name'], '恢复歌单');
    expect(savedBackup.single['audios'].single['path'], song.path);
  });

  for (final invalid in <Object?>[
    null,
    {'version': 1, 'playlists': 'broken'},
    {'version': 99, 'playlists': []},
    {
      'version': 1,
      'playlists': [false]
    },
    {
      'version': 1,
      'playlists': [
        {'name': 42, 'audios': []}
      ]
    },
    {
      'version': 1,
      'playlists': [
        {'name': 'bad', 'audios': null}
      ]
    },
    {
      'version': 1,
      'playlists': [
        {
          'name': 'bad',
          'audios': [false]
        }
      ]
    },
    {
      'version': 1,
      'playlists': [
        {
          'name': 'bad',
          'audios': [{}]
        }
      ]
    },
    {
      'version': 1,
      'playlists': [
        {'name': 'bad', 'audios': [], 'isSystem': 1}
      ]
    },
  ]) {
    test('rejects invalid schema without replacing memory: $invalid', () async {
      final existing = Playlist('内存歌单', {});
      PLAYLISTS.add(existing);
      final revision = playlistRevision.value;
      final primary = File('${directory.path}/playlists.json');
      final contents = jsonEncode(invalid);
      await primary.writeAsString(contents);

      await expectLater(readPlaylists(store: store), throwsFormatException);

      expect(PLAYLISTS, [same(existing)]);
      expect(playlistRevision.value, revision);
      expect(await primary.readAsString(), contents);
      expect(File('${primary.path}.bak').existsSync(), isFalse);
    });
  }

  test(
      'failed load preserves both copies and blocks shutdown saves until reload',
      () async {
    final existing = Playlist('内存歌单', {});
    PLAYLISTS.add(existing);
    final primary = File('${directory.path}/playlists.json');
    final backup = File('${primary.path}.bak');
    const badPrimary =
        '{"version":1,"playlists":[{"name":"partial","audios":[]},false]}';
    const badBackup = '{broken backup';
    await primary.writeAsString(badPrimary);
    await backup.writeAsString(badBackup);

    await expectLater(readPlaylists(store: store), throwsFormatException);
    await expectLater(
      savePlaylists(store: LocalJsonStore(directory), rethrowOnError: true),
      throwsStateError,
    );

    expect(PLAYLISTS, [same(existing)]);
    expect(await primary.readAsString(), badPrimary);
    expect(await backup.readAsString(), badBackup);

    await primary.writeAsString(jsonEncode({
      'version': 1,
      'playlists': [Playlist(likedPlaylistName, {}, isSystem: true).toMap()],
    }));
    await readPlaylists(store: store);
    await savePlaylists(store: store, rethrowOnError: true);
    expect(PLAYLISTS.single.name, likedPlaylistName);
  });

  test('migration write failure preserves memory and recovered backup',
      () async {
    final existing = Playlist('内存歌单', {});
    PLAYLISTS.add(existing);
    final song = makeAudio('D:/music/recovered.flac');
    final primary = File('${directory.path}/playlists.json');
    final backup = File('${primary.path}.bak');
    final goodBackup = jsonEncode([
      {
        'name': '恢复歌单',
        'audios': [song.toMap()],
      },
    ]);
    await primary.writeAsString('{broken primary');
    await backup.writeAsString(goodBackup);
    final failingStore =
        LocalJsonStore(directory, moveFile: (source, destination) async {
      if (source.path.endsWith('playlists.json.tmp')) {
        throw const FileSystemException('simulated migration failure');
      }
      await source.rename(destination.path);
    });

    await expectLater(
      readPlaylists(store: failingStore),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      savePlaylists(store: store, rethrowOnError: true),
      throwsStateError,
    );

    expect(PLAYLISTS, [same(existing)]);
    expect(await primary.readAsString(), goodBackup);
    expect(await backup.readAsString(), goodBackup);
  });

  test('serializes overlapping saves using snapshots taken at invocation',
      () async {
    final delayed = _BlockingStore(directory);
    PLAYLISTS.add(Playlist('first', {}));
    final first = savePlaylists(store: delayed, rethrowOnError: true);
    await delayed.started.future;
    PLAYLISTS.add(Playlist('second', {}));
    final second = savePlaylists(store: delayed, rethrowOnError: true);
    PLAYLISTS.add(Playlist('not yet saved', {}));
    await Future<void>.delayed(Duration.zero);
    final writesBeforeRelease = delayed.snapshots.length;
    delayed.release.complete();
    await Future.wait([first, second]);

    expect(writesBeforeRelease, 1);
    expect(delayed.snapshots[0]['playlists'], hasLength(1));
    expect(delayed.snapshots[1]['playlists'], hasLength(2));
  });

  test('a failed ordinary save does not poison the next queued save', () async {
    final delayed = _BlockingStore(directory, failFirst: true);
    PLAYLISTS.add(Playlist('first', {}));
    final first = expectLater(
      savePlaylists(store: delayed, rethrowOnError: true),
      throwsA(isA<FileSystemException>()),
    );
    await delayed.started.future;
    PLAYLISTS.add(Playlist('second', {}));
    final second = savePlaylists(store: delayed, rethrowOnError: true);
    delayed.release.complete();
    await Future.wait([first, second]);

    expect(delayed.snapshots, hasLength(2));
    expect(delayed.snapshots.last['playlists'], hasLength(2));
  });

  test('rejects shutdown saves while a playlist load is still pending',
      () async {
    final primary = File('${directory.path}/playlists.json');
    final saved = {
      'version': 1,
      'playlists': [Playlist(likedPlaylistName, {}, isSystem: true).toMap()],
    };
    await primary.writeAsString(jsonEncode(saved));
    final delayed = _BlockingReadStore(directory);
    final loading = readPlaylists(store: delayed);
    await delayed.started.future;
    Object? saveError;
    try {
      await savePlaylists(store: store, rethrowOnError: true);
    } catch (error) {
      saveError = error;
    }
    // Let the save settle before completing the read, so a stale empty snapshot
    // cannot overwrite the file before the delayed load resumes.
    delayed.release.complete();
    await loading;

    expect(saveError, isA<StateError>());
    expect(jsonDecode(await primary.readAsString()), saved);
    expect(PLAYLISTS.single.name, likedPlaylistName);
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
      {
        'name': likedPlaylistName,
        'audios': [first.toMap()],
      },
      {
        'name': likedPlaylistName,
        'audios': [first.toMap(), second.toMap()],
      },
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

  test('rejects the protected name for regular playlist creation and rename',
      () {
    expect(
      () => Playlist(likedPlaylistName, {}),
      throwsArgumentError,
    );
    expect(createPlaylist(likedPlaylistName), isFalse);
    expect(PLAYLISTS, isEmpty);

    final regular = Playlist('regular', {});
    expect(regular.rename(likedPlaylistName), isFalse);
    expect(regular.name, 'regular');
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

  test(
      'adds unique songs, updates revision, and exposes the latest artwork source',
      () {
    final first = makeAudio('D:/music/first.flac');
    final latest = makeAudio('D:/music/latest.flac');
    final playlist = Playlist('regular', {});
    final revision = playlistRevision.value;

    expect(playlist.latestAudio, isNull);
    expect(addAudioToPlaylist(playlist, first), isTrue);
    expect(playlistRevision.value, revision + 1);
    expect(addAudioToPlaylist(playlist, latest), isTrue);
    expect(playlist.latestAudio, same(latest));
    expect(addAudioToPlaylist(playlist, latest), isFalse);
    expect(playlist.audios.keys, [first.path, latest.path]);
  });

  test('removes songs through the playlist helper and updates revision', () {
    final song = makeAudio('D:/music/remove.flac');
    final playlist = Playlist('regular', {song.path: song});
    final revision = playlistRevision.value;

    expect(removeAudioFromPlaylist(playlist, song.path), isTrue);
    expect(playlist.audios, isEmpty);
    expect(playlistRevision.value, revision + 1);
    expect(removeAudioFromPlaylist(playlist, song.path), isFalse);
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

class _BlockingStore extends LocalJsonStore {
  _BlockingStore(super.directory, {this.failFirst = false});

  final bool failFirst;
  final started = Completer<void>();
  final release = Completer<void>();
  final snapshots = <Map>[];

  @override
  Future<void> writeAtomically(String fileName, Object value) async {
    snapshots.add(value as Map);
    if (snapshots.length == 1) {
      started.complete();
      await release.future;
      if (failFirst) {
        throw const FileSystemException('simulated first save failure');
      }
    }
  }
}

class _BlockingReadStore extends LocalJsonStore {
  _BlockingReadStore(super.directory);

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<T?> readValidated<T>(
    String fileName,
    T Function(Object? value) parse,
  ) async {
    started.complete();
    await release.future;
    return super.readValidated(fileName, parse);
  }
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
