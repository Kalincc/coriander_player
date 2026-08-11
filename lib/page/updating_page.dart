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
  const UpdatingStateView({super.key, required this.indexPath});

  final Directory indexPath;

  @override
  State<UpdatingStateView> createState() => _UpdatingStateViewState();
}

class _UpdatingStateViewState extends State<UpdatingStateView> {
  late final LibraryUpdateCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = _createCoordinator(widget.indexPath);
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
              .initializePlaybackData(AudioLibrary.instance.audioCollection);
        },
        refreshLyrics: LyricSearchIndex.instance.refreshCurrentLibrary,
      );

  Future<void> _updateAndContinue() async {
    try {
      await _coordinator.update();
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
        ],
      ),
    );
  }
}
