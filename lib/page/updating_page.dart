import 'dart:async';
import 'dart:io';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/library_update_coordinator.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class UpdatingPage extends StatelessWidget {
  const UpdatingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: FutureBuilder(
          future: getAppDataDir(),
          builder: (context, snapshot) {
            if (snapshot.data == null) {
              return const Center(child: Text('Fail to get app data dir.'));
            }
            return UpdatingStateView(indexPath: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class UpdatingStateView extends StatefulWidget {
  const UpdatingStateView({
    super.key,
    required this.indexPath,
    this.coordinatorFactory,
    this.showRebuildDialog,
    this.onUpdated,
  });

  final Directory indexPath;
  final LibraryUpdateCoordinator Function(Directory indexPath)?
      coordinatorFactory;
  final Future<bool?> Function(BuildContext context)? showRebuildDialog;
  final VoidCallback? onUpdated;

  @override
  State<UpdatingStateView> createState() => _UpdatingStateViewState();
}

class _UpdatingStateViewState extends State<UpdatingStateView> {
  late final LibraryUpdateCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = widget.coordinatorFactory?.call(widget.indexPath) ??
        _createCoordinator(widget.indexPath);
    _coordinator.addListener(_onProgressChanged);
    unawaited(_updateAndContinue());
  }

  LibraryUpdateCoordinator _createCoordinator(Directory indexPath) =>
      LibraryUpdateCoordinator(
        scan: () async => updateIndex(indexPath: indexPath.path),
        reloadLibrary: AudioLibrary.initFromIndex,
        reconcileAppData: () async {
          await readPlaylists();
          await readLyricSources();
          await PlayService.instance
              .reconcilePlaybackData(AudioLibrary.instance.audioCollection);
        },
        refreshLyrics: LyricSearchIndex.instance.refreshCurrentLibrary,
      );

  Future<void> _updateAndContinue() async {
    try {
      await _coordinator.update();
      final onUpdated = widget.onUpdated;
      if (onUpdated != null) {
        onUpdated();
        return;
      }
      if (mounted) {
        context.go(app_paths.START_PAGES[AppPreference.instance.startPage]);
      }
    } catch (error, trace) {
      LOGGER.e(error, stackTrace: trace);
    }
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _rebuildLibraryAndRetry() async {
    final rebuilt = await (widget.showRebuildDialog?.call(context) ??
        showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AudioLibraryEditorDialog(),
        ));
    if (rebuilt == true && mounted) {
      await _updateAndContinue();
    }
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onProgressChanged);
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _coordinator.progress;
    final error = progress.error;

    return SizedBox(
      width: 400,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LinearProgressIndicator(
            value: progress.action?.progress,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 8),
          Text(
            error == null ? progress.action?.message ?? '' : '$error',
            style: TextStyle(
                color: error == null ? scheme.onSurface : scheme.error),
            textAlign: TextAlign.center,
          ),
          if (_requiresLibraryRebuild(error)) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('rebuild-library-button'),
              onPressed: _rebuildLibraryAndRetry,
              icon: const Icon(Icons.folder_open),
              label: const Text('打开文件夹管理并完整重建'),
            ),
          ],
        ],
      ),
    );
  }
}

bool _requiresLibraryRebuild(Object? error) =>
    error.toString().contains('index is missing configured scan roots');
