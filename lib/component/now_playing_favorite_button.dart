import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class NowPlayingFavoriteButton extends StatelessWidget {
  const NowPlayingFavoriteButton({
    super.key,
    required this.audio,
    this.isLiked,
    this.onToggle,
  });

  final Audio? audio;
  final bool Function(Audio audio)? isLiked;
  final Future<void> Function(Audio audio)? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentAudio = audio;
    return ListenableBuilder(
      listenable: playlistRevision,
      builder: (context, _) {
        final liked =
            currentAudio != null && (isLiked ?? _isLiked)(currentAudio);
        return IconButton(
          tooltip: liked ? '从喜欢的歌曲中移除' : '添加到喜欢的歌曲',
          onPressed: currentAudio == null
              ? null
              : () async {
                  await (onToggle ?? _toggleLiked)(currentAudio);
                },
          icon: Icon(Symbols.favorite, fill: liked ? 1 : 0),
          color: scheme.onSecondaryContainer,
        );
      },
    );
  }
}

bool _isLiked(Audio audio) => isLiked(audio);

Future<void> _toggleLiked(Audio audio) => toggleLiked(audio);
