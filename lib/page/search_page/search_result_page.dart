import 'dart:async';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/component/album_tile.dart';
import 'package:coriander_player/component/artist_tile.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/component/lyric_search_result_tile.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/page/search_page/local_search_controller.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class SearchResultPage extends StatefulWidget {
  final String initialQuery;
  final LyricSearchIndex? lyricIndex;

  const SearchResultPage({
    super.key,
    required this.initialQuery,
    this.lyricIndex,
  });

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late final LyricSearchIndex index;
  late final LocalSearchController searchController;
  late final TextEditingController searchBarController;
  late bool _wasIndexSyncing;

  @override
  void initState() {
    super.initState();
    index = widget.lyricIndex ?? LyricSearchIndex.instance;
    final initialQuery = widget.initialQuery.trim();
    searchBarController = TextEditingController(text: initialQuery);
    searchController = LocalSearchController(lyricIndex: index);
    _wasIndexSyncing = index.progress.isSyncing;
    index.addListener(_handleIndexChanged);
    unawaited(searchController.search(initialQuery));
  }

  void _handleIndexChanged() {
    final isSyncing = index.progress.isSyncing;
    if (_wasIndexSyncing && !isSyncing) _runSearch();
    _wasIndexSyncing = isSyncing;
  }

  void _runSearch() {
    final query = searchBarController.text.trim();
    if (query.isEmpty) return;
    if (searchBarController.text != query) {
      searchBarController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    unawaited(searchController.search(query));
  }

  List<_SearchResultPageBody> buildContent(UnionSearchResult result) => [
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.all,
          index: index,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.music,
          index: index,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.lyrics,
          index: index,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.artist,
          index: index,
        ),
        _SearchResultPageBody(
          result: result,
          filter: _SearchResultFilter.album,
          index: index,
        ),
      ];

  @override
  void dispose() {
    index.removeListener(_handleIndexChanged);
    searchBarController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: Hero(
                  tag: SEARCH_BAR_KEY,
                  child: ValueListenableBuilder<LocalSearchState>(
                    valueListenable: searchController,
                    builder: (context, state, _) => TextField(
                      controller: searchBarController,
                      decoration: InputDecoration(
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: state.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Symbols.search),
                        ),
                        hintText: '搜索歌曲、艺术家、专辑、歌词',
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _runSearch(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                type: MaterialType.transparency,
                child: TabBar(
                  tabs: _SearchResultFilter.values
                      .map((filter) => Tab(text: filter.name))
                      .toList(),
                ),
              ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: ValueListenableBuilder<LocalSearchState>(
                    valueListenable: searchController,
                    builder: (context, state, _) => TabBarView(
                      children: buildContent(state.result),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SearchResultFilter {
  all('所有'),
  music('音乐'),
  lyrics('歌词'),
  artist('艺术家'),
  album('专辑');

  const _SearchResultFilter(this.name);
  final String name;
}

class _SearchResultPageBody extends StatelessWidget {
  const _SearchResultPageBody({
    required this.result,
    required this.filter,
    required this.index,
  });

  final UnionSearchResult result;
  final _SearchResultFilter filter;
  final LyricSearchIndex index;

  Widget buildContentHeader(
    ColorScheme scheme,
    _SearchResultFilter contentType,
  ) =>
      SliverToBoxAdapter(
        child: filter == _SearchResultFilter.all
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  contentType.name,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const SizedBox(height: 8),
      );

  List<Widget> buildMusicResultContent(ColorScheme scheme) => [
        buildContentHeader(scheme, _SearchResultFilter.music),
        SliverList.builder(
          itemCount: result.audios.length,
          itemBuilder: (context, i) {
            final item = result.audios[i];
            return AudioTile(
              audioIndex: 0,
              playlist: [item],
              action: IconButton(
                onPressed: () {
                  context.push(app_paths.AUDIOS_PAGE, extra: item);
                },
                icon: const Icon(Symbols.location_on),
              ),
            );
          },
        ),
      ];

  List<Widget> buildLyricResultContent(ColorScheme scheme) {
    final progress = index.progress;
    return [
      buildContentHeader(scheme, _SearchResultFilter.lyrics),
      if (progress.isSyncing)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '正在建立本地歌词索引：已处理 '
              '${progress.processed}/${progress.total}',
            ),
          ),
        ),
      if (result.lyrics.isNotEmpty)
        SliverList.builder(
          itemCount: result.lyrics.length,
          itemBuilder: (context, i) {
            final match = result.lyrics[i];
            return LyricSearchResultTile(
              match: match,
              query: result.query,
              onLocate: () {
                context.push(app_paths.AUDIOS_PAGE, extra: match.audio);
              },
            );
          },
        )
      else if (!progress.isSyncing)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('未找到匹配的本地歌词')),
          ),
        ),
    ];
  }

  List<Widget> buildArtistResultContent(ColorScheme scheme) => [
        buildContentHeader(scheme, _SearchResultFilter.artist),
        SliverList.builder(
          itemCount: result.artists.length,
          itemBuilder: (context, i) => ArtistTile(artist: result.artists[i]),
        ),
      ];

  List<Widget> buildAlbumResultContent(ColorScheme scheme) => [
        buildContentHeader(scheme, _SearchResultFilter.album),
        SliverList.builder(
          itemCount: result.album.length,
          itemBuilder: (context, i) => AlbumTile(album: result.album[i]),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slivers = <Widget>[];
    switch (filter) {
      case _SearchResultFilter.all:
        if (result.audios.isNotEmpty) {
          slivers.addAll(buildMusicResultContent(scheme));
        }
        if (result.lyrics.isNotEmpty) {
          slivers.addAll(buildLyricResultContent(scheme));
        }
        if (result.artists.isNotEmpty) {
          slivers.addAll(buildArtistResultContent(scheme));
        }
        if (result.album.isNotEmpty) {
          slivers.addAll(buildAlbumResultContent(scheme));
        }
        break;
      case _SearchResultFilter.music:
        slivers.addAll(buildMusicResultContent(scheme));
        break;
      case _SearchResultFilter.lyrics:
        slivers.addAll(buildLyricResultContent(scheme));
        break;
      case _SearchResultFilter.artist:
        slivers.addAll(buildArtistResultContent(scheme));
        break;
      case _SearchResultFilter.album:
        slivers.addAll(buildAlbumResultContent(scheme));
        break;
    }
    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 96)));
    return CustomScrollView(slivers: slivers);
  }
}
