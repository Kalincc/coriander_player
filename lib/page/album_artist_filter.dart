import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/artist_name_normalizer.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

List<String> filterArtistNames(Iterable<String> names, String query) {
  final normalized = normalizeArtistName(query.trim()).toLowerCase();
  final result = names
      .where((name) => name.toLowerCase().contains(normalized))
      .toList(growable: false);
  result.sort((a, b) => a.localeCompareTo(b));
  return result;
}

List<Album> albumsForArtist({
  required Iterable<Album> allAlbums,
  required Map<String, Artist> artists,
  required String? artistName,
}) {
  final artist =
      artistName == null ? null : artists[normalizeArtistName(artistName)];
  return artist == null
      ? List<Album>.from(allAlbums)
      : List<Album>.from(artist.albumsMap.values);
}

class AlbumArtistFilterButton extends StatelessWidget {
  const AlbumArtistFilterButton({
    super.key,
    required this.artistNames,
    required this.selection,
    required this.onSelected,
  });

  final List<String> artistNames;
  final AlbumBrowseSelection selection;
  final ValueChanged<AlbumBrowseSelection> onSelected;

  String get label => switch (selection.mode) {
        AlbumBrowseMode.grouped => '分类：按艺术家',
        AlbumBrowseMode.uncategorized => '分类：无分类',
        AlbumBrowseMode.artist => '艺术家：${selection.artistName}',
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton.tonal(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => _AlbumArtistFilterDialog(
            artistNames: artistNames,
            onSelected: onSelected,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _AlbumArtistFilterDialog extends StatefulWidget {
  const _AlbumArtistFilterDialog({
    required this.artistNames,
    required this.onSelected,
  });

  final List<String> artistNames;
  final ValueChanged<AlbumBrowseSelection> onSelected;

  @override
  State<_AlbumArtistFilterDialog> createState() =>
      _AlbumArtistFilterDialogState();
}

class _AlbumArtistFilterDialogState extends State<_AlbumArtistFilterDialog> {
  String query = '';

  void select(AlbumBrowseSelection selection) {
    widget.onSelected(selection);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final artistNames = filterArtistNames(widget.artistNames, query);
    return Dialog(
      child: SizedBox(
        width: 360,
        height: 480,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '专辑分类',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Symbols.close),
                  ),
                ],
              ),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索艺术家',
                  prefixIcon: Icon(Symbols.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('分类：按艺术家'),
                onTap: () => select(const AlbumBrowseSelection.grouped()),
              ),
              ListTile(
                title: const Text('分类：无分类'),
                onTap: () => select(const AlbumBrowseSelection.uncategorized()),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: artistNames.length,
                  itemBuilder: (context, index) {
                    final artistName = artistNames[index];
                    return ListTile(
                      title: Text(artistName),
                      onTap: () =>
                          select(AlbumBrowseSelection.artist(artistName)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
