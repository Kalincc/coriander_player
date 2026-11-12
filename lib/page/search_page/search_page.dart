import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/artist_name_normalizer.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class UnionSearchResult {
  final String query;

  final List<Audio> audios = [];
  final List<Artist> artists = [];
  final List<Album> album = [];
  final List<LyricSearchMatch> lyrics = [];

  UnionSearchResult(this.query);

  factory UnionSearchResult.copyOf(UnionSearchResult source) =>
      UnionSearchResult(source.query)
        ..audios.addAll(source.audios)
        ..artists.addAll(source.artists)
        ..album.addAll(source.album)
        ..lyrics.addAll(source.lyrics);

  static UnionSearchResult search(
    String query, {
    LyricSearchIndex? lyricIndex,
  }) {
    final normalizedQuery = query.trim();
    final result = UnionSearchResult(normalizedQuery);
    if (normalizedQuery.isEmpty) return result;

    final queryInLowerCase = normalizedQuery.toLowerCase();
    final artistQueryInLowerCase =
        normalizeArtistName(normalizedQuery).toLowerCase();
    final library = AudioLibrary.instance;

    for (int i = 0; i < library.audioCollection.length; i++) {
      if (library.audioCollection[i].title
          .toLowerCase()
          .contains(queryInLowerCase)) {
        result.audios.add(library.audioCollection[i]);
      }
    }

    for (Artist item in library.artistCollection.values) {
      if (item.name.toLowerCase().contains(artistQueryInLowerCase)) {
        result.artists.add(item);
      }
    }

    for (Album item in library.albumCollection.values) {
      if (item.name.toLowerCase().contains(queryInLowerCase)) {
        result.album.add(item);
      }
    }
    result.lyrics.addAll(
      (lyricIndex ?? LyricSearchIndex.instance).search(
        normalizedQuery,
        library.audioCollection,
      ),
    );
    return result;
  }
}

final searchFocusRequest = ValueNotifier(0);

class LocalSearchField extends StatefulWidget {
  const LocalSearchField({
    super.key,
    this.controller,
    this.autofocus = false,
    required this.onSubmitted,
    required this.suffix,
  });

  final TextEditingController? controller;
  final bool autofocus;
  final ValueChanged<String> onSubmitted;
  final Widget suffix;

  @override
  State<LocalSearchField> createState() => _LocalSearchFieldState();
}

class _LocalSearchFieldState extends State<LocalSearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    searchFocusRequest.addListener(_focusWhenVisible);
  }

  void _focusWhenVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          TickerMode.of(context) &&
          ModalRoute.isCurrentOf(context) != false) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    searchFocusRequest.removeListener(_focusWhenVisible);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        onFocusChange: HotkeysHelper.onFocusChanges,
        child: Hero(
          tag: 'local-search-input',
          child: Material(
            type: MaterialType.transparency,
            child: TextField(
              focusNode: _focus,
              controller: widget.controller,
              autofocus: widget.autofocus,
              decoration: InputDecoration(
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: widget.suffix,
                ),
                hintText: '搜索歌曲、艺术家、专辑、歌词',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: widget.onSubmitted,
            ),
          ),
        ),
      );
}

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preference = AppPreference.instance;
    void search(String query) {
      final term = query.trim();
      if (term.isEmpty) return;
      preference.rememberSearch(term);
      context.push(app_paths.SEARCH_RESULT_PAGE, extra: term);
    }

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('搜索', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                LocalSearchField(
                  autofocus: true,
                  suffix: const Icon(Symbols.search),
                  onSubmitted: search,
                ),
                ValueListenableBuilder<List<String>>(
                  valueListenable: preference.recentSearches,
                  builder: (context, terms, _) => terms.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('最近搜索'),
                                TextButton(
                                  onPressed: () {
                                    preference.recentSearches.value = const [];
                                    preference.save();
                                  },
                                  child: const Text('清空记录'),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final term in terms)
                                  ActionChip(
                                    label: Text(term,
                                        overflow: TextOverflow.ellipsis),
                                    onPressed: () => search(term),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
