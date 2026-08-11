import 'dart:async';
import 'dart:io';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LibraryStartupLoader {
  const LibraryStartupLoader({
    required this.reloadLibrary,
    required this.loadPlaylists,
    required this.loadLyricSources,
    required this.loadLyricIndex,
    required this.loadPlaybackHistory,
  });

  final Future<void> Function() reloadLibrary;
  final Future<void> Function() loadPlaylists;
  final Future<void> Function() loadLyricSources;
  final Future<void> Function() loadLyricIndex;
  final Future<void> Function() loadPlaybackHistory;

  Future<void> load() async {
    await reloadLibrary();
    await loadPlaylists();
    await loadLyricSources();
    await loadLyricIndex();
    await loadPlaybackHistory();
  }
}

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
    this.loadLibrary,
    this.onUpdated,
  });

  final Directory indexPath;
  final Future<void> Function()? loadLibrary;
  final VoidCallback? onUpdated;

  @override
  State<UpdatingStateView> createState() => _UpdatingStateViewState();
}

class _UpdatingStateViewState extends State<UpdatingStateView> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAndContinue());
  }

  Future<void> _loadAndContinue() async {
    try {
      final loadLibrary = widget.loadLibrary ??
          LibraryStartupLoader(
            reloadLibrary: () => AudioLibrary.initFromIndex(
              indexFile: File(
                '${widget.indexPath.path}${Platform.pathSeparator}index.json',
              ),
            ),
            loadPlaylists: readPlaylists,
            loadLyricSources: readLyricSources,
            loadLyricIndex: LyricSearchIndex.instance.load,
            loadPlaybackHistory: () => PlayService.instance
                .initializePlaybackData(AudioLibrary.instance.audioCollection),
          ).load;
      await loadLibrary();
      final onUpdated = widget.onUpdated;
      if (onUpdated != null) {
        onUpdated();
        return;
      }
      if (mounted) {
        context.go(app_paths.START_PAGES[AppPreference.instance.startPage]);
      }
    } catch (error, trace) {
      if (mounted) setState(() => _error = error);
      LOGGER.e(error, stackTrace: trace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    return SizedBox(
      width: 400,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LinearProgressIndicator(
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 8),
          Text(
            error == null ? '正在加载音乐库…' : '音乐库加载失败：$error',
            key: error == null ? null : const Key('library-startup-error'),
            style: TextStyle(
                color: error == null ? scheme.onSurface : scheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
