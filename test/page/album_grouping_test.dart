import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browse selections represent grouped, uncategorized, and artist modes',
      () {
    const grouped = AlbumBrowseSelection.grouped();
    const uncategorized = AlbumBrowseSelection.uncategorized();
    const artist = AlbumBrowseSelection.artist('周杰伦');

    expect(grouped.mode, AlbumBrowseMode.grouped);
    expect(uncategorized.mode, AlbumBrowseMode.uncategorized);
    expect(artist.mode, AlbumBrowseMode.artist);
    expect(artist.artistName, '周杰伦');
  });

  test('groups artists by album count and sorts albums only within groups', () {
    final shared = Album(name: 'Shared');
    final alpha = Album(name: 'Alpha');
    final beta = Album(name: 'Beta');
    final artistA = Artist(name: 'Artist A')
      ..albumsMap.addAll({'Shared': shared, 'Beta': beta});
    final artistB = Artist(name: 'Artist B')
      ..albumsMap.addAll({'Shared': shared, 'Alpha': alpha});
    final artistC = Artist(name: 'Artist C')..albumsMap['Alpha'] = alpha;
    final empty = Artist(name: 'Empty');

    final groups = buildAlbumArtistGroups(
      artists: [artistC, empty, artistB, artistA],
      sortAlbums: (a, b) => b.name.compareTo(a.name),
    );

    expect(groups.map((group) => group.artist.name), [
      'Artist A',
      'Artist B',
      'Artist C',
    ]);
    expect(groups[0].albums.map((album) => album.name), ['Shared', 'Beta']);
    expect(groups[1].albums.map((album) => album.name), ['Shared', 'Alpha']);
    expect(identical(groups[0].albums.first, groups[1].albums.first), isTrue);
  });
}
