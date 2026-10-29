import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/listening_report.dart';
import 'package:coriander_player/library/playback_history_models.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String title, String artist,
        {String? albumArtist, int disc = 0, int track = 1}) =>
    Audio(title, artist, '精选', track, 180, 320, 44100,
        'D:/music/$artist/$title.flac', 1, 1, 'test',
        albumArtist: albumArtist, disc: disc);

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));

  test('same-title albums belonging to different artists stay separate', () {
    final first = song('One', '张学友');
    final second = song('Two', '孙燕姿');
    final library = AudioLibrary.forTesting([first, second]);
    expect(library.albumCollection, hasLength(2));
    expect(library.albumForAudio(first)!.works, [first]);
    expect(library.albumForAudio(second)!.works, [second]);
    expect(
        library.artistForName('张学友')!.albumsMap.values.single.works, [first]);
  });

  test('album artist joins compilation tracks and owns its browse group', () {
    final first = song('One', '歌手甲', albumArtist: '群星', disc: 1);
    final second = song('Two', '歌手乙', albumArtist: '群星', disc: 2);
    final library = AudioLibrary.forTesting([first, second]);
    final album = library.albumCollection.values.single;
    expect(album.works, [first, second]);
    expect(album.artistsMap.keys, containsAll(['歌手甲', '歌手乙']));
    expect(library.artistsForAudio(first).map((a) => a.name), ['歌手甲']);
    final groups = buildAlbumArtistGroups(
      artists: library.artistCollection.values,
      sortAlbums: (a, b) => a.name.compareTo(b.name),
    );
    expect(groups.map((g) => g.artist.name), ['群星']);
    expect(groups.single.albums, [album]);
  });

  test('canonical artist spelling and artist order share an album identity',
      () {
    expect(song('One', '張學友').albumKey, song('Two', '张学友').albumKey);
    expect(song('One', '甲/乙').albumKey, song('Two', '乙/甲').albumKey);
    expect(song('One', '甲', albumArtist: '  群星 ').albumKey,
        song('Two', '乙', albumArtist: '群星').albumKey);
  });

  test('legacy metadata and new metadata round-trip without losing fields', () {
    final legacy = song('Old', 'Artist').toMap()
      ..remove('album_artist')
      ..remove('disc')
      ..remove('disc_total');
    expect(Audio.fromMap(legacy).albumArtist, isNull);
    expect(Audio.fromMap(legacy).disc, 0);
    final updated = song('New', 'Artist', albumArtist: 'Album artist', disc: 2)
      ..discTotal = 2;
    final restored = Audio.fromMap(updated.toMap());
    expect(restored.albumArtist, 'Album artist');
    expect(restored.disc, 2);
    expect(restored.discTotal, 2);
  });

  test('renamed album artist resolves to the owner, not a track performer', () {
    final previous = AudioLibrary.forTesting([
      song('One', '歌手甲', albumArtist: '旧合辑艺术家'),
    ]).artistForName('旧合辑艺术家')!;
    final current = AudioLibrary.forTesting([
      song('One', '歌手甲', albumArtist: '新合辑艺术家'),
    ]);
    expect(current.refreshedArtist(previous)!.name, '新合辑艺术家');
  });

  test('moving one track does not redirect an album that still exists', () {
    final old = AudioLibrary.forTesting([
      song('Moved', 'Artist'),
      song('Kept', 'Artist'),
    ]).albumCollection.values.single;
    final moved = song('Moved', 'Artist')..album = 'Other album';
    final kept = song('Kept', 'Artist');
    final current = AudioLibrary.forTesting([moved, kept]);
    expect(current.refreshedAlbum(old)!.works, [same(kept)]);
  });

  test('disc then track order avoids interleaving and labels missing tags', () {
    final tracks = [
      song('D2T1', 'Artist', disc: 2),
      song('D1T2', 'Artist', disc: 1, track: 2),
      song('D1T1', 'Artist', disc: 1),
    ]..sort(compareAlbumTracks);
    expect(tracks.map((a) => a.title), ['D1T1', 'D1T2', 'D2T1']);
    final album = AudioLibrary.forTesting(tracks).albumCollection.values.single;
    expect(album.hasMultipleDiscs, isTrue);
    expect(tracks.last.trackLabel(includeDisc: true), 'CD2 · 01');
    expect(song('Unknown', 'Artist', track: 0).trackLabel(includeDisc: true),
        'CD? · --');
  });

  test('reports distinguish same-title albums but combine compilation discs',
      () {
    final tracks = [
      song('A', '甲'),
      song('B', '乙'),
      song('C', '甲', albumArtist: '群星', disc: 1),
      song('D', '乙', albumArtist: '群星', disc: 2),
    ];
    final now = DateTime(2026, 10, 29);
    final report = buildListeningReport(
      tracks.map((a) => PlaybackHistoryEvent(
            path: a.path,
            startedAt: now,
            listened: const Duration(seconds: 30),
            qualified: true,
          )),
      ReportPeriod.currentMonth(now),
      {for (final a in tracks) a.path: a},
    );
    expect(report.albumCount, 3);
    expect(report.albumRanks.first.key, tracks.last.albumKey);
    expect(report.albumRanks.first.listened, const Duration(seconds: 60));
  });
}

class _Api implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
