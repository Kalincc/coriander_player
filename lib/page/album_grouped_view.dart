import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/album_grouping.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:flutter/material.dart';

typedef AlbumGroupedItemBuilder = Widget Function(
  BuildContext context,
  Album album,
);

class AlbumGroupedView extends StatelessWidget {
  const AlbumGroupedView({
    super.key,
    required this.groups,
    required this.contentView,
    required this.itemBuilder,
  });

  final List<AlbumArtistGroup> groups;
  final ContentView contentView;
  final AlbumGroupedItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: CustomScrollView(
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                child: Text(
                  '${group.artist.name} · ${group.albums.length} 张专辑',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (contentView == ContentView.list)
              SliverFixedExtentList.builder(
                itemCount: group.albums.length,
                itemExtent: 64,
                itemBuilder: (context, index) =>
                    itemBuilder(context, group.albums[index]),
              )
            else
              SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemCount: group.albums.length,
                itemBuilder: (context, index) =>
                    itemBuilder(context, group.albums[index]),
              ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }
}
