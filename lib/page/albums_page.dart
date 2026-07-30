import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/album_tile.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_artist_filter.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  String? _selectedArtistName;

  @override
  Widget build(BuildContext context) {
    final library = AudioLibrary.instance;
    final selectedExists = _selectedArtistName == null ||
        library.artistCollection.containsKey(_selectedArtistName);
    final effectiveArtistName = selectedExists ? _selectedArtistName : null;
    final contentList = albumsForArtist(
      allAlbums: library.albumCollection.values,
      artists: library.artistCollection,
      artistName: effectiveArtistName,
    );
    final artistNames = filterArtistNames(library.artistCollection.keys, '');

    return UniPage<Album>(
      key: ValueKey(effectiveArtistName ?? '__all_albums__'),
      pref: AppPreference.instance.albumsPagePref,
      title: "专辑",
      subtitle: effectiveArtistName == null
          ? '${contentList.length} 张专辑'
          : '该艺术家的 ${contentList.length} 张专辑',
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) =>
          AlbumTile(album: item),
      primaryAction: AlbumArtistFilterButton(
        artistNames: artistNames,
        selectedArtistName: effectiveArtistName,
        onSelected: (name) => setState(() => _selectedArtistName = name),
      ),
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      emptyState: const Center(child: Text('该艺术家没有专辑')),
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "标题",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.name.localeCompareTo(b.name));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.name.localeCompareTo(a.name));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.music_note,
          name: "作品数量",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.works.length.compareTo(b.works.length));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.works.length.compareTo(a.works.length));
                break;
            }
          },
        ),
      ],
    );
  }
}
