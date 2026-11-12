import 'dart:async';
import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/library_update_coordinator.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/page/settings_page/artist_separator_editor.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class DefaultLyricSourceControl extends StatefulWidget {
  const DefaultLyricSourceControl({super.key});

  @override
  State<DefaultLyricSourceControl> createState() =>
      _DefaultLyricSourceControlState();
}

class _DefaultLyricSourceControlState extends State<DefaultLyricSourceControl> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: '首选歌词来源',
      action: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: true, icon: Icon(Symbols.cloud_off), label: Text('本地')),
          ButtonSegment(
              value: false, icon: Icon(Symbols.cloud), label: Text('在线')),
        ],
        selected: {settings.localLyricFirst},
        onSelectionChanged: (newSelection) async {
          if (newSelection.first == settings.localLyricFirst) return;
          setState(() => settings.localLyricFirst = newSelection.first);
          await settings.saveSettings();
        },
      ),
    );
  }
}

// Owned by the application, not the dialog: closing the dialog never cancels it.
final _libraryScan = ValueNotifier<LibraryUpdateCoordinator?>(null);

Widget _watchScan(Widget Function(LibraryUpdateCoordinator?) builder) =>
    ValueListenableBuilder<LibraryUpdateCoordinator?>(
      valueListenable: _libraryScan,
      builder: (context, task, _) => task == null
          ? builder(null)
          : ListenableBuilder(
              listenable: task, builder: (_, __) => builder(task)),
    );

class LibrarySettings extends StatelessWidget {
  const LibrarySettings({super.key});

  @override
  Widget build(BuildContext context) => _watchScan((task) {
        final busy = task?.progress.isUpdating == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsTile(
              description: '文件夹管理',
              action: FilledButton.icon(
                icon: const Icon(Symbols.folder),
                label: Text(busy ? '查看扫描进度' : '文件夹管理'),
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const AudioLibraryEditorDialog(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ArtistSeparatorEditor(enabled: !busy),
          ],
        );
      });
}

class AudioLibraryEditorDialog extends StatefulWidget {
  const AudioLibraryEditorDialog({
    super.key,
    this.applicationSupportDirectory,
    this.buildIndex = buildIndexFromFoldersRecursively,
  });

  final Future<Directory>? applicationSupportDirectory;
  final BuildIndexStream buildIndex;

  @override
  State<AudioLibraryEditorDialog> createState() =>
      _AudioLibraryEditorDialogState();
}

class _AudioLibraryEditorDialogState extends State<AudioLibraryEditorDialog> {
  var _draftLibrary = AudioLibrary.instance;
  late final _folders = _draftLibrary.scanRoots.toList();

  Future<void> _scanNow() async {
    if (_folders.isEmpty || _libraryScan.value?.progress.isUpdating == true)
      return;
    final task = LibraryUpdateCoordinator.staged(
      indexDirectory: widget.applicationSupportDirectory ?? getAppDataDir(),
      folders: _folders,
      buildIndex: widget.buildIndex,
      reconcileAppData: () async {
        await PlayService.instance
            .reconcilePlaybackData(AudioLibrary.instance.audioCollection);
        AudioLibrary.revision.value++;
      },
      refreshLyrics: LyricSearchIndex.instance.syncCurrentLibrary,
    );
    _libraryScan.value = task;
    try {
      await task.update();
    } catch (error, trace) {
      LOGGER.e('[library scan] $error', stackTrace: trace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AudioLibrary.watch(context);
    return _watchScan((task) {
      final progress = task?.progress;
      final busy = progress?.isUpdating == true;
      final library = AudioLibrary.instance;
      if (!busy && !identical(_draftLibrary, library)) {
        _draftLibrary = library;
        _folders
          ..clear()
          ..addAll(library.scanRoots);
      }
      return AlertDialog(
        title: const Text('管理文件夹'),
        content: SizedBox(
          width: 450,
          height: 290,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (library.scanRoots.isEmpty)
                const Text(
                  '旧版索引未保存扫描根目录。请重新选择文件夹后再扫描；当前音乐仍可播放。',
                  key: Key('legacy-library-roots-warning'),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _folders.length,
                  itemBuilder: (context, i) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_folders[i],
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: '移除文件夹',
                      onPressed: busy
                          ? null
                          : () => setState(() => _folders.removeAt(i)),
                      icon: const Icon(Symbols.delete),
                    ),
                  ),
                ),
              ),
              if (busy)
                LinearProgressIndicator(
                  value: task!.canCancel
                      ? scanIndicatorValue(progress?.action)
                      : null,
                ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                Text(
                  progress.message,
                  key: const Key('library-scan-status'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: progress.error == null
                      ? null
                      : TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!busy)
            TextButton(
              onPressed: () {
                final picker = DirectoryPicker()..title = '选择文件夹';
                final selected = picker.getDirectory();
                if (selected != null && !_folders.contains(selected.path)) {
                  setState(() => _folders.add(selected.path));
                }
              },
              child: const Text('添加'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(busy ? '后台继续' : '关闭'),
          ),
          if (busy)
            FilledButton.tonal(
              onPressed:
                  task!.canCancel ? () => unawaited(task.cancel()) : null,
              child: const Text('取消扫描'),
            )
          else
            FilledButton(
              key: const Key('scan-library-now-button'),
              onPressed: _folders.isEmpty ? null : _scanNow,
              child: const Text('立即扫描'),
            ),
        ],
      );
    });
  }
}
