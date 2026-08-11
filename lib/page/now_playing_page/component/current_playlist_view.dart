import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_queue_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView({
    super.key,
    this.queueService,
    this.onPlayIndex,
  });

  final PlaybackQueueService? queueService;
  final ValueChanged<int>? onPlayIndex;

  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  PlaybackService? _playbackService;
  late final ScrollController scrollController;

  PlaybackService? get _playback => widget.queueService == null
      ? _playbackService ??= PlayService.instance.playbackService
      : null;

  PlaybackQueueService? get _queue =>
      widget.queueService ?? _playback?.playbackQueueService;

  void _toNowPlaying() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        (_playback?.playlistIndex ?? 0) * 56.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: (_playback?.playlistIndex ?? 0) * 56.0,
    );
    _playback?.addListener(_toNowPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final queue = _queue;
    final playback = _playback;
    final listenable = queue ?? playback!;

    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final items = queue?.items ?? playback!.playlist.value;
          final currentIndex =
              queue != null ? queue.currentIndex : playback!.playlistIndex;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '播放列表',
                        style: TextStyle(
                          color: scheme.onSecondaryContainer,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear queue',
                      onPressed: items.isEmpty || queue == null
                          ? null
                          : () {
                              if (playback != null) {
                                playback.clearQueue();
                              } else {
                                queue.clear();
                              }
                            },
                      icon: const Icon(Symbols.clear_all),
                      color: scheme.onSecondaryContainer,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Queue is empty'))
                    : ReorderableListView.builder(
                        scrollController: scrollController,
                        itemCount: items.length,
                        onReorder: queue == null
                            ? (_, __) {}
                            : (oldIndex, newIndex) =>
                                queue.reorder(oldIndex, newIndex),
                        itemBuilder: (context, index) => _PlaylistViewItem(
                          key: ValueKey(items[index].path),
                          audio: items[index],
                          index: index,
                          current: index == currentIndex,
                          onPlay: () {
                            final callback = widget.onPlayIndex;
                            if (callback != null) {
                              callback(index);
                            } else {
                              playback?.playIndexOfPlaylist(index);
                            }
                          },
                          onRemove: queue == null
                              ? null
                              : () {
                                  if (playback != null) {
                                    playback.removeFromQueue(index);
                                  } else {
                                    queue.removeAt(index);
                                  }
                                },
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
    _playbackService?.removeListener(_toNowPlaying);
    scrollController.dispose();
    super.dispose();
  }
}

class _PlaylistViewItem extends StatelessWidget {
  const _PlaylistViewItem({
    super.key,
    required this.audio,
    required this.index,
    required this.current,
    required this.onPlay,
    required this.onRemove,
  });

  final Audio audio;
  final int index;
  final bool current;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;

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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove from queue',
            onPressed: onRemove,
            icon: const Icon(Symbols.close),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Symbols.drag_handle),
          ),
        ],
      ),
    );
  }
}
