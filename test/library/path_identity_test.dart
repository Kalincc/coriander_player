import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/audio_path_key.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path, {String title = 'Song'}) =>
    Audio(title, 'Artist', 'Album', 1, 180, 320, 44100, path, 1, 1, 'Lofty');

void main() {
  late Directory directory;
  late LocalJsonStore store;
  final now = DateTime(2026, 10, 29, 12);

  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));
  setUp(() async {
    PLAYLISTS.clear();
    LYRIC_SOURCES.clear();
    directory = await Directory.systemTemp.createTemp('coriander-paths-');
    store = LocalJsonStore(directory);
  });
  tearDown(() async {
    PLAYLISTS.clear();
    LYRIC_SOURCES.clear();
    await directory.delete(recursive: true);
  });

  test('path identity preserves distinct drives and non-Windows paths', () {
    expect(audioPathKey(r'D:\Music\A\..\Song.flac'),
        audioPathKey(r'\\?\d:\music\song.flac'));
    expect(audioPathKey(r'\\?\UNC\Server\Share\Song.flac'),
        audioPathKey('//server/share/song.flac'));
    expect(audioPathKey(r'D:\Music\Song.flac'),
        isNot(audioPathKey(r'E:\Music\Song.flac')));
    expect(audioPathKey('/Music/Song.flac'), '/Music/Song.flac');
    expect(audioPathKey('/music/song.flac'), '/music/song.flac');
  });

  test('lyric preferences match aliases while retaining the original I/O path',
      () {
    const original = r'\\?\D:\Music\Song.flac';
    final first = LyricSource(LyricSourceType.local);
    setLyricSourceForPath(original, first);

    expect(lyricSourceForPath('d:/music/song.flac'), same(first));
    expect(LYRIC_SOURCES.keys, [original]);
    const current = 'D:/Music/Song.flac';
    final replacement = LyricSource(LyricSourceType.qq, qqSongId: 123);
    setLyricSourceForPath(current, replacement);
    expect(LYRIC_SOURCES.keys, [current]);
    expect(lyricSourceForPath(original), same(replacement));
  });

  test('rescan retains favorites and refreshes metadata across Windows aliases',
      () async {
    final old = _audio(r'D:\Music\Artist\Song.flac', title: 'Old');
    final current = _audio(r'\\?\d:\music\artist\Song.flac', title: 'New');
    final otherDrive = _audio(r'E:\Music\Artist\Song.flac');
    PLAYLISTS.add(Playlist(
        likedPlaylistName,
        {
          old.path: old,
          otherDrive.path: otherDrive,
        },
        isSystem: true));

    await reconcilePlaylistAudios([current], store: store);

    expect(PLAYLISTS.single.audios.keys, [current.path]);
    expect(PLAYLISTS.single.audios.values.single, same(current));
    expect(isLiked(current), isTrue);
    await readPlaylists(store: store);
    expect(isLiked(current), isTrue);
  });

  test('favorites treat slash case and extended path aliases as one song',
      () async {
    final first = _audio('D:/Music/Artist/Song.flac');
    final alias = _audio(r'\\?\d:\music\artist\song.flac');
    PLAYLISTS
        .add(Playlist(likedPlaylistName, {first.path: first}, isSystem: true));

    expect(isLiked(alias), isTrue);
    expect(addAudioToPlaylist(PLAYLISTS.single, alias), isFalse);
    await toggleLiked(alias, store: store);
    expect(PLAYLISTS.single.audios, isEmpty);
  });

  test('rescan retains history events across Windows path aliases', () async {
    final old = _audio(r'D:\Music\Song.flac');
    final current = _audio(r'\\?\d:\music\song.flac');
    final history = PlaybackHistoryService(store: store, now: () => now);
    history.startSession(old);
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();

    await history.reconcileLibrary([current]);

    expect(history.events.single.path, current.path);
    expect(history.events.single.listened, const Duration(seconds: 30));
    final reloaded = PlaybackHistoryService(store: store, now: () => now);
    await reloaded.load();
    expect(reloaded.events.single.path, current.path);
  });

  test('rescan retains an active history session across UNC aliases', () async {
    final old = _audio(r'\\Server\Share\Music\Song.flac');
    final current = _audio(r'\\?\UNC\server\share\music\song.flac');
    final history = PlaybackHistoryService(store: store, now: () => now);
    history.startSession(old);
    history.recordPosition(const Duration(seconds: 20));

    await history.reconcileLibrary([current]);
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();

    expect(history.events.single.path, current.path);
    expect(history.events.single.listened, const Duration(seconds: 30));
  });

  test(
      'shutdown flush reports write failure and can retry without losing history',
      () async {
    final failing = _RetryStore(directory);
    final history = PlaybackHistoryService(store: failing, now: () => now);
    history.startSession(_audio('D:/Music/Song.flac'));
    history.recordPosition(const Duration(seconds: 30));

    await expectLater(
        history.endSession(), throwsA(isA<FileSystemException>()));
    expect(history.events, hasLength(1));
    failing.fail = false;
    await history.endSession(flush: true);

    final reloaded = PlaybackHistoryService(store: failing, now: () => now);
    await reloaded.load();
    expect(reloaded.events, hasLength(1));
  });

  test('startup migration keeps unmatched records until an explicit rescan',
      () async {
    final old = _audio('D:/Music/Song.flac');
    final offline = _audio('E:/Offline/Song.flac');
    final current = _audio(r'\\?\d:\music\song.flac');
    PLAYLISTS.add(Playlist('Saved', {old.path: old, offline.path: offline}));
    final history = PlaybackHistoryService(store: store, now: () => now);
    for (final audio in [old, offline]) {
      history.startSession(audio);
      history.recordPosition(const Duration(seconds: 30));
      await history.endSession();
    }

    await reconcilePlaylistAudios([current],
        store: store, removeMissing: false);
    await history.reconcileLibrary([current], removeMissing: false);

    expect(PLAYLISTS.single.audios.keys, [current.path, offline.path]);
    expect(history.events.map((event) => event.path),
        [current.path, offline.path]);
  });

  test('failed history load prevents shutdown from overwriting the saved file',
      () async {
    final file = File('${directory.path}/play_history.json');
    const corrupt = '{"version":1,"events":"invalid"}';
    await file.writeAsString(corrupt);
    final history = PlaybackHistoryService(store: store, now: () => now);

    await expectLater(history.load(), throwsFormatException);
    await expectLater(history.endSession(flush: true), throwsStateError);
    expect(await file.readAsString(), corrupt);
    await file.writeAsString('{"version":1,"events":[]}');
    await history.load();
    await history.endSession(flush: true);
    expect(history.events, isEmpty);
  });
}

class _RetryStore extends LocalJsonStore {
  _RetryStore(super.directory);
  bool fail = true;

  @override
  Future<void> writeAtomically(String fileName, Object value) async {
    if (fail) throw const FileSystemException('simulated disk full');
    await super.writeAtomically(fileName, value);
  }
}

class _TestRustLibApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
