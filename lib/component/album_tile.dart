import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class AlbumTile extends StatelessWidget {
  const AlbumTile({
    super.key,
    required this.album,
    this.coverWall = false,
  });

  final Album album;
  final bool coverWall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurface)),
        if (album.albumArtist.isNotEmpty)
          Text(album.albumArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    final placeholder = Icon(
      Symbols.broken_image,
      size: 48,
      color: scheme.onSurface,
    );
    return Tooltip(
      message: '${album.name} · ${album.albumArtist}',
      child: InkWell(
        onTap: () => context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album),
        borderRadius: BorderRadius.circular(8.0),
        child: coverWall
            ? LayoutBuilder(builder: (context, constraints) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ArtworkThumbnail(
                      image: album.works.firstOrNull?.mediumCover,
                      size: constraints.maxWidth,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: labels,
                    ),
                  ],
                );
              })
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    FutureBuilder(
                      future: album.works.first.cover,
                      builder: (context, snapshot) {
                        if (snapshot.data == null) {
                          return placeholder;
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image(
                            image: snapshot.data!,
                            width: 48.0,
                            height: 48.0,
                            errorBuilder: (_, __, ___) => placeholder,
                          ),
                        );
                      },
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: labels,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
