import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/album_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_artist_filter.dart';
import 'package:coriander_player/page/album_grouped_view.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  AlbumBrowseSelection _selection = const AlbumBrowseSelection.grouped();

  List<SortMethodDesc<Album>> get _sortMethods => [
        SortMethodDesc(
          icon: Symbols.title,
          name: '标题',
          method: (list, order) =>
              list.sort((a, b) => _compareAlbums(a, b, 0, order)),
        ),
        SortMethodDesc(
          icon: Symbols.music_note,
          name: '作品数量',
          method: (list, order) =>
              list.sort((a, b) => _compareAlbums(a, b, 1, order)),
        ),
      ];

  int _compareAlbums(Album a, Album b, int method, SortOrder order) {
    final comparison = method == 0
        ? a.name.localeCompareTo(b.name)
        : a.works.length.compareTo(b.works.length);
    final ordered = order == SortOrder.ascending ? comparison : -comparison;
    return ordered != 0 ? ordered : a.name.localeCompareTo(b.name);
  }

  @override
  Widget build(BuildContext context) {
    final library = AudioLibrary.instance;
    final artistNames = filterArtistNames(library.artistCollection.keys, '');
    final selection = _effectiveSelection(library);
    final filter = AlbumArtistFilterButton(
      artistNames: artistNames,
      selection: selection,
      onSelected: (value) => setState(() => _selection = value),
    );

    if (selection.mode == AlbumBrowseMode.grouped) {
      return _buildGroupedPage(library, filter);
    }

    final artistName =
        selection.mode == AlbumBrowseMode.artist ? selection.artistName : null;
    final contentList = albumsForArtist(
      allAlbums: library.albumCollection.values,
      artists: library.artistCollection,
      artistName: artistName,
    );
    return UniPage<Album>(
      key: ValueKey(artistName ?? '__uncategorized_albums__'),
      pref: AppPreference.instance.albumsPagePref,
      title: '专辑',
      subtitle: artistName == null
          ? '${contentList.length} 张专辑'
          : '该艺术家的 ${contentList.length} 张专辑',
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) =>
          AlbumTile(album: item),
      primaryAction: filter,
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      emptyState: const Center(child: Text('该艺术家没有专辑')),
      sortMethods: _sortMethods,
    );
  }

  AlbumBrowseSelection _effectiveSelection(AudioLibrary library) {
    if (_selection.mode != AlbumBrowseMode.artist) return _selection;
    return library.artistCollection.containsKey(_selection.artistName)
        ? _selection
        : const AlbumBrowseSelection.uncategorized();
  }

  Widget _buildGroupedPage(
    AudioLibrary library,
    AlbumArtistFilterButton filter,
  ) {
    final preference = AppPreference.instance.albumsPagePref;
    final sortMethods = _sortMethods;
    final sortIndex = preference.sortMethod.clamp(0, sortMethods.length - 1);
    final groups = buildAlbumArtistGroups(
      artists: library.artistCollection.values,
      sortAlbums: (a, b) =>
          _compareAlbums(a, b, sortIndex, preference.sortOrder),
    );

    return PageScaffold(
      title: '专辑',
      subtitle: '${library.albumCollection.length} 张专辑 · ${groups.length} 位艺术家',
      actions: [
        filter,
        SortMethodComboBox<Album>(
          sortMethods: sortMethods,
          contentList: library.albumCollection.values.toList(),
          currSortMethod: sortMethods[sortIndex],
          setSortMethod: (method) => setState(() {
            preference.sortMethod = sortMethods.indexOf(method);
          }),
        ),
        SortOrderSwitch<Album>(
          sortOrder: preference.sortOrder,
          setSortOrder: (order) => setState(() {
            preference.sortOrder = order;
          }),
        ),
        ContentViewSwitch<Album>(
          contentView: preference.contentView,
          setContentView: (view) => setState(() {
            preference.contentView = view;
          }),
        ),
      ],
      body: groups.isEmpty
          ? const Center(child: Text('没有专辑'))
          : AlbumGroupedView(
              groups: groups,
              contentView: preference.contentView,
              itemBuilder: (context, album) => AlbumTile(album: album),
            ),
    );
  }
}
