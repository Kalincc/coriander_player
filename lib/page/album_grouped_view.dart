import 'dart:math' as math;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Match the existing grid delegate's column calculation and spacing.
          final columns = contentView == ContentView.list
              ? 1
              : math.max(
                  1,
                  (constraints.maxWidth /
                          (gridDelegate.maxCrossAxisExtent +
                              gridDelegate.crossAxisSpacing))
                      .ceil());
          final rows = <(AlbumArtistGroup, int?)>[
            for (final group in groups) ...[
              (group, null),
              for (var start = 0; start < group.albums.length; start += columns)
                (group, start),
            ],
          ];
          return CustomScrollView(slivers: [
            // One lazy delegate: separate slivers otherwise lay out the first
            // album of every off-screen artist group to estimate scroll extent.
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final (group, start) = rows[index];
                if (start == null) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: Text(
                        '${group.artist.name} · ${group.albums.length} 张专辑',
                        style: Theme.of(context).textTheme.titleMedium),
                  );
                }
                final hasNextRow = start + columns < group.albums.length;
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: hasNextRow && contentView == ContentView.table
                          ? gridDelegate.mainAxisSpacing
                          : 0),
                  child: SizedBox(
                    height: gridDelegate.mainAxisExtent,
                    child: Row(children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0)
                          SizedBox(width: gridDelegate.crossAxisSpacing),
                        Expanded(
                            child: start + column < group.albums.length
                                ? itemBuilder(
                                    context, group.albums[start + column])
                                : const SizedBox.shrink()),
                      ],
                    ]),
                  ),
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
          ]);
        },
      ),
    );
  }
}
