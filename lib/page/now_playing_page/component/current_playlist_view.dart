import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart' as playlists;
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class CurrentPlaylistView extends StatefulWidget {
  const CurrentPlaylistView(
      {super.key, this.playbackService, this.saveAsPlaylist});
  final PlaybackPlaylistController? playbackService;
  final Future<void> Function(String name, List<Audio> items)? saveAsPlaylist;
  @override
  State<CurrentPlaylistView> createState() => _CurrentPlaylistViewState();
}

class _CurrentPlaylistViewState extends State<CurrentPlaylistView> {
  static const _rowHeight = 72.0;
  late PlaybackPlaylistController _playback;
  late final ScrollController _scroll;
  Object? _currentKey;
  bool _followCurrent = true;

  @override
  void initState() {
    super.initState();
    _playback = widget.playbackService ?? PlayService.instance.playbackService;
    _scroll = ScrollController();
    _attach();
  }

  Object? _activeKey() => _playback.playlist.value.isEmpty
      ? null
      : _playback.queueItemKey(_playback.playlistIndex);

  void _attach() {
    _currentKey = _activeKey();
    _playback.addListener(_queueChanged);
    _playback.playlist.addListener(_queueChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _locate(animate: false));
  }

  void _detach() {
    _playback.removeListener(_queueChanged);
    _playback.playlist.removeListener(_queueChanged);
  }

  @override
  void didUpdateWidget(covariant CurrentPlaylistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackService != widget.playbackService) {
      _detach();
      _playback =
          widget.playbackService ?? PlayService.instance.playbackService;
      _attach();
    }
  }

  void _queueChanged() {
    final next = _activeKey();
    if (next == _currentKey) return;
    _currentKey = next;
    if (_followCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  void _locate({bool animate = true}) {
    if (!mounted || !_scroll.hasClients) return;
    final offset = (_playback.playlistIndex * _rowHeight)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    if (animate) {
      _scroll.animateTo(offset,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(offset);
    }
  }

  void _edit(bool changed, String message) {
    if (!changed) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(
            label: '撤销', onPressed: () => _playback.undoQueueEdit())));
  }

  Future<void> _save() async {
    final snapshot = List<Audio>.of(_playback.playlist.value);
    playlists.Playlist? created;
    final name = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _QueuePlaylistDialog(
            onSave: widget.saveAsPlaylist ??
                (name, items) async {
                  // A failed write keeps this one new playlist in memory for retry.
                  created ??= playlists.createPlaylistFromAudios(name, items);
                  await playlists.savePlaylists(rethrowOnError: true);
                },
            items: snapshot));
    if (!mounted || name == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('队列已保存为歌单“$name”')));
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: ListenableBuilder(
          listenable: Listenable.merge([_playback, _playback.playlist]),
          builder: (context, _) {
            final items = _playback.playlist.value;
            final current = _playback.playlistIndex;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('播放队列 · ${items.length} 首',
                                style: Theme.of(context).textTheme.titleLarge),
                            Wrap(children: [
                              IconButton(
                                  tooltip: '定位当前歌曲',
                                  icon: const Icon(Icons.my_location),
                                  onPressed: items.isEmpty
                                      ? null
                                      : () {
                                          _followCurrent = true;
                                          _locate();
                                        }),
                              IconButton(
                                  tooltip: '撤销队列操作',
                                  icon: const Icon(Icons.undo),
                                  onPressed: _playback.canUndoQueueEdit
                                      ? () => _playback.undoQueueEdit()
                                      : null),
                              IconButton(
                                  tooltip: '保存队列为歌单',
                                  icon: const Icon(Icons.playlist_add),
                                  onPressed: items.isEmpty ? null : _save),
                              IconButton(
                                  tooltip: '清空待播，保留当前歌曲',
                                  icon: const Icon(Icons.playlist_remove),
                                  onPressed: items.length <= 1
                                      ? null
                                      : () => _edit(
                                          _playback.clearUpcomingQueue(),
                                          '已清空待播，当前歌曲继续播放')),
                            ]),
                          ])),
                  Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text('播放队列为空'))
                          : NotificationListener<UserScrollNotification>(
                              onNotification: (notification) {
                                if (notification.direction !=
                                    ScrollDirection.idle) {
                                  _followCurrent = false;
                                }
                                return false;
                              },
                              child: ReorderableListView.builder(
                                scrollController: _scroll,
                                itemExtent: _rowHeight,
                                itemCount: items.length,
                                buildDefaultDragHandles: false,
                                onReorder: (oldIndex, newIndex) => _edit(
                                    _playback.moveQueueItem(oldIndex, newIndex),
                                    '已调整队列顺序'),
                                itemBuilder: (context, index) => SizedBox(
                                    key:
                                        ValueKey(_playback.queueItemKey(index)),
                                    height: _rowHeight,
                                    child: ListTile(
                                      selected: index == current,
                                      leading: index == current
                                          ? const Icon(Icons.play_arrow)
                                          : Text('${index + 1}'),
                                      title: Text(items[index].title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                          '${items[index].artist} - ${items[index].album}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      onTap: () =>
                                          _playback.playIndexOfPlaylist(index),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                key: ValueKey(
                                                    'remove-queue-$index'),
                                                tooltip: index == current
                                                    ? '正在播放，保留当前歌曲'
                                                    : '移除待播歌曲',
                                                icon: const Icon(Icons
                                                    .remove_circle_outline),
                                                onPressed: index == current
                                                    ? null
                                                    : () => _edit(
                                                        _playback
                                                            .removeQueueItem(
                                                                index),
                                                        '已移除待播歌曲')),
                                            ReorderableDragStartListener(
                                                index: index,
                                                child: const Tooltip(
                                                    message: '拖动调整顺序',
                                                    child: Padding(
                                                        padding:
                                                            EdgeInsets.all(8),
                                                        child: Icon(Icons
                                                            .drag_handle)))),
                                          ]),
                                    )),
                              ),
                            )),
                ]);
          },
        ),
      );

  @override
  void dispose() {
    _detach();
    _scroll.dispose();
    super.dispose();
  }
}

class _QueuePlaylistDialog extends StatefulWidget {
  const _QueuePlaylistDialog({required this.items, required this.onSave});
  final List<Audio> items;
  final Future<void> Function(String, List<Audio>) onSave;
  @override
  State<_QueuePlaylistDialog> createState() => _QueuePlaylistDialogState();
}

class _QueuePlaylistDialogState extends State<_QueuePlaylistDialog> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _attemptedName;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    final name = _attemptedName ?? _name.text.trim();
    if (_attemptedName == null &&
        (name.isEmpty ||
            playlists.isReservedPlaylistName(name) ||
            playlists.PLAYLISTS.any((item) => item.name == name))) {
      setState(() => _error = '请填写未使用的歌单名称，不能使用“我喜欢”');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _attemptedName = name;
    });
    try {
      await widget.onSave(name, widget.items);
      if (mounted) Navigator.pop(context, name);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存未完成，请重试。队列不受影响。\n$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: const Text('保存队列为歌单'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('保存当前队列的独立副本，重复文件只保留一首。'),
            Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                    controller: _name,
                    readOnly: _attemptedName != null,
                    decoration:
                        InputDecoration(labelText: '歌单名称', errorText: _error),
                    onSubmitted: (_) => _save())),
          ]),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? '保存中…'
                    : _attemptedName == null
                        ? '保存'
                        : '重试保存')),
          ],
        ),
      );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}
