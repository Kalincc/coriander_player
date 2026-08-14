import 'package:coriander_player/library/audio_library.dart';

enum AlbumBrowseMode { grouped, uncategorized, artist }

class AlbumBrowseSelection {
  const AlbumBrowseSelection.grouped()
      : mode = AlbumBrowseMode.grouped,
        artistName = null;

  const AlbumBrowseSelection.uncategorized()
      : mode = AlbumBrowseMode.uncategorized,
        artistName = null;

  const AlbumBrowseSelection.artist(this.artistName)
      : mode = AlbumBrowseMode.artist;

  final AlbumBrowseMode mode;
  final String? artistName;

  @override
  bool operator ==(Object other) =>
      other is AlbumBrowseSelection &&
      other.mode == mode &&
      other.artistName == artistName;

  @override
  int get hashCode => Object.hash(mode, artistName);
}

class AlbumArtistGroup {
  const AlbumArtistGroup({required this.artist, required this.albums});

  final Artist artist;
  final List<Album> albums;
}

List<AlbumArtistGroup> buildAlbumArtistGroups({
  required Iterable<Artist> artists,
  required Comparator<Album> sortAlbums,
}) {
  final groups = artists
      .map((artist) {
        final albums = artist.albumsMap.values.toList()..sort(sortAlbums);
        return AlbumArtistGroup(artist: artist, albums: albums);
      })
      .where((group) => group.albums.isNotEmpty)
      .toList();

  groups.sort((a, b) {
    final byCount = b.albums.length.compareTo(a.albums.length);
    return byCount != 0 ? byCount : a.artist.name.compareTo(b.artist.name);
  });
  return groups;
}
