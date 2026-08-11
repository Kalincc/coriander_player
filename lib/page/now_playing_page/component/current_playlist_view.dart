import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView({
    super.key,
    this.playbackService,
  });

  final PlaybackPlaylistController? playbackService;

  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  PlaybackService? _defaultPlaybackService;
  late final ScrollController scrollController;

  PlaybackPlaylistController get _playback =>
      widget.playbackService ??
      (_defaultPlaybackService ??= PlayService.instance.playbackService);

  void _toNowPlaying() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        _playback.playlistIndex * 56.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: _playback.playlistIndex * 56.0,
    );
    _playback.addListener(_toNowPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playback = _playback;

    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: playback,
        builder: (context, _) {
          final items = playback.playlist.value;
          final currentIndex = playback.playlistIndex;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  '播放列表',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Queue is empty'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: items.length,
                        itemBuilder: (context, index) => _PlaylistViewItem(
                          audio: items[index],
                          current: index == currentIndex,
                          onPlay: () => playback.playIndexOfPlaylist(index),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _playback.removeListener(_toNowPlaying);
    scrollController.dispose();
    super.dispose();
  }
}

class _PlaylistViewItem extends StatelessWidget {
  const _PlaylistViewItem({
    required this.audio,
    required this.current,
    required this.onPlay,
  });

  final Audio audio;
  final bool current;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: current,
      selectedTileColor: scheme.primaryContainer,
      title: Text(audio.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${audio.artist} - ${audio.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onPlay,
    );
  }
}
