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

enum _AlbumLayout {
  list('列表', Symbols.list),
  table('表格', Symbols.table),
  coverWall('封面墙', Symbols.grid_view);

  const _AlbumLayout(this.label, this.icon);
  final String label;
  final IconData icon;
}

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
    final library = AudioLibrary.watch(context);
    final artistNames = filterArtistNames(library.artistCollection.keys, '');
    final selection = _effectiveSelection(library);
    final filter = AlbumArtistFilterButton(
      artistNames: artistNames,
      selection: selection,
      onSelected: (value) => setState(() => _selection = value),
    );

    final appPreference = AppPreference.instance;
    final preference = appPreference.albumsPagePref;
    final sortMethods = _sortMethods;
    final sortIndex = preference.sortMethod.clamp(0, sortMethods.length - 1);
    final layout = appPreference.albumCoverWall
        ? _AlbumLayout.coverWall
        : preference.contentView == ContentView.list
            ? _AlbumLayout.list
            : _AlbumLayout.table;
    final grouped = selection.mode == AlbumBrowseMode.grouped;
    final artistName =
        selection.mode == AlbumBrowseMode.artist ? selection.artistName : null;
    final groups = grouped
        ? buildAlbumArtistGroups(
            artists: library.artistCollection.values,
            sortAlbums: (a, b) =>
                _compareAlbums(a, b, sortIndex, preference.sortOrder),
          )
        : const <AlbumArtistGroup>[];
    final albums = grouped
        ? const <Album>[]
        : (albumsForArtist(
            allAlbums: library.albumCollection.values,
            artists: library.artistCollection,
            artistName: artistName,
          )..sort(
            (a, b) => _compareAlbums(a, b, sortIndex, preference.sortOrder)));
    final coverWall = layout == _AlbumLayout.coverWall;

    return PageScaffold(
      title: '专辑',
      subtitle: grouped
          ? '${library.albumCollection.length} 张专辑 · ${groups.length} 位艺术家'
          : '${artistName == null ? '' : '该艺术家的 '}${albums.length} 张专辑',
      actions: [
        filter,
        SortMethodComboBox<Album>(
          sortMethods: sortMethods,
          contentList: albums,
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
        PopupMenuButton<_AlbumLayout>(
          tooltip: '切换专辑视图；现在：${layout.label}',
          icon: Icon(layout.icon),
          initialValue: layout,
          itemBuilder: (_) => [
            for (final item in _AlbumLayout.values)
              PopupMenuItem(value: item, child: Text(item.label)),
          ],
          onSelected: (view) => setState(() {
            appPreference.albumCoverWall = view == _AlbumLayout.coverWall;
            if (!appPreference.albumCoverWall) {
              preference.contentView = view == _AlbumLayout.list
                  ? ContentView.list
                  : ContentView.table;
            }
          }),
        ),
      ],
      body: groups.isEmpty && albums.isEmpty
          ? Center(child: Text(artistName == null ? '没有专辑' : '该艺术家没有专辑'))
          : AlbumGroupedView(
              key: ValueKey((selection, layout)),
              groups: groups,
              albums: albums,
              contentView: preference.contentView,
              coverWall: coverWall,
              itemBuilder: (context, album) => AlbumTile(
                album: album,
                coverWall: coverWall,
              ),
            ),
    );
  }

  AlbumBrowseSelection _effectiveSelection(AudioLibrary library) {
    if (_selection.mode != AlbumBrowseMode.artist) return _selection;
    return library.artistCollection.containsKey(_selection.artistName)
        ? _selection
        : const AlbumBrowseSelection.uncategorized();
  }
}
