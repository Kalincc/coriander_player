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
    this.groups = const [],
    this.albums = const [],
    required this.contentView,
    required this.itemBuilder,
    this.coverWall = false,
  });

  final List<AlbumArtistGroup> groups;
  final List<Album> albums;
  final ContentView contentView;
  final AlbumGroupedItemBuilder itemBuilder;
  final bool coverWall;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Match the existing grid delegate's column calculation and spacing.
          final spacing = coverWall ? 12.0 : gridDelegate.crossAxisSpacing;
          final columns = coverWall
              ? math.max(1, (constraints.maxWidth / 200).round())
              : contentView == ContentView.list
                  ? 1
                  : math.max(
                      1,
                      (constraints.maxWidth /
                              (gridDelegate.maxCrossAxisExtent +
                                  gridDelegate.crossAxisSpacing))
                          .ceil());
          final rowHeight = coverWall
              ? (constraints.maxWidth - spacing * (columns - 1)) / columns +
                  MediaQuery.textScalerOf(context).scale(52)
              : gridDelegate.mainAxisExtent;
          final rows = <(AlbumArtistGroup?, int?)>[
            for (var start = 0; start < albums.length; start += columns)
              (null, start),
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
                  final section = group!;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: Text(
                        '${section.artist.name} · ${section.albums.length} 张专辑',
                        style: Theme.of(context).textTheme.titleMedium),
                  );
                }
                final items = group?.albums ?? albums;
                final hasNextRow = start + columns < items.length;
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: hasNextRow &&
                              (coverWall || contentView == ContentView.table)
                          ? (coverWall ? spacing : gridDelegate.mainAxisSpacing)
                          : 0),
                  child: SizedBox(
                    height: rowHeight,
                    child: Row(children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) SizedBox(width: spacing),
                        Expanded(
                            child: start + column < items.length
                                ? itemBuilder(context, items[start + column])
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
