import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

typedef BuildIndexStream = Stream<IndexActionState> Function({
  required List<String> folders,
  required String indexPath,
});

enum LibraryUpdatePhase {
  idle,
  scanning,
  cancelling,
  publishing,
  reconciling,
  lyrics,
  completed,
  cancelled,
  failed,
}

double? scanIndicatorValue(IndexActionState? action) {
  final value = action?.progress;
  return value != null && value >= 0 && value <= 1 ? value : null;
}

@immutable
class LibraryUpdateProgress {
  const LibraryUpdateProgress({
    this.action,
    this.phase = LibraryUpdatePhase.idle,
    this.error,
  });

  final IndexActionState? action;
  final LibraryUpdatePhase phase;
  final Object? error;

  bool get isUpdating => switch (phase) {
        LibraryUpdatePhase.scanning ||
        LibraryUpdatePhase.cancelling ||
        LibraryUpdatePhase.publishing ||
        LibraryUpdatePhase.reconciling ||
        LibraryUpdatePhase.lyrics =>
          true,
        _ => false,
      };

  String get message => switch (phase) {
        LibraryUpdatePhase.idle => '',
        LibraryUpdatePhase.scanning => action?.message ?? '正在准备扫描…',
        LibraryUpdatePhase.cancelling => '正在取消扫描，等待当前文件处理结束…',
        LibraryUpdatePhase.publishing => '正在验证并更新音乐库索引…',
        LibraryUpdatePhase.reconciling => '正在同步歌单和播放数据…',
        LibraryUpdatePhase.lyrics => '正在更新本地歌词索引…',
        LibraryUpdatePhase.completed => '音乐库已更新',
        LibraryUpdatePhase.cancelled => '扫描已取消，原音乐库保持不变',
        LibraryUpdatePhase.failed => '音乐库更新失败：$error',
      };
}

class LibraryUpdateCoordinator extends ChangeNotifier {
  LibraryUpdateCoordinator({
    required this.scan,
    required this.reloadLibrary,
    required this.refreshLyrics,
    required this.reconcileAppData,
    this.stopScan,
    this.cleanUp,
  });

  factory LibraryUpdateCoordinator.staged({
    required Future<Directory> indexDirectory,
    required List<String> folders,
    BuildIndexStream buildIndex = buildIndexFromFoldersRecursively,
    required Future<void> Function() refreshLyrics,
    required Future<void> Function() reconcileAppData,
  }) {
    final roots = List<String>.unmodifiable(folders);
    Directory? staging;
    var cancelled = false;
    return LibraryUpdateCoordinator(
      scan: () async {
        final parent = await indexDirectory;
        staging = await parent.createTemp('library-scan-');
        if (cancelled) return const Stream.empty();
        return buildIndex(folders: roots, indexPath: staging!.path);
      },
      stopScan: () async {
        cancelled = true;
        final directory = staging;
        if (directory != null) {
          await File(path.join(directory.path, '.scan-cancel'))
              .writeAsString('cancel', flush: true);
        }
      },
      reloadLibrary: () async {
        final parent = await indexDirectory;
        final source = File(path.join(staging!.path, 'index.json'));
        final target = path.join(parent.path, 'index.json');
        await AudioLibrary.initFromIndex(
          indexFile: source,
          // Staging is on the same volume as the live index.
          beforePublish: () async {
            await source.rename(target);
          },
        );
      },
      reconcileAppData: reconcileAppData,
      refreshLyrics: refreshLyrics,
      cleanUp: () async {
        final directory = staging;
        if (directory == null) return;
        for (final name in [
          '.scan-cancel',
          'index.json',
          'index.json.tmp',
          'index.json.bak'
        ]) {
          final file = File(path.join(directory.path, name));
          if (await file.exists()) await file.delete();
        }
        await directory.delete();
      },
    );
  }

  final Future<Stream<IndexActionState>> Function() scan;
  final Future<void> Function() reloadLibrary;
  final Future<void> Function() refreshLyrics;
  final Future<void> Function() reconcileAppData;
  final Future<void> Function()? stopScan;
  final Future<void> Function()? cleanUp;

  LibraryUpdateProgress progress = const LibraryUpdateProgress();
  Future<void>? _activeUpdate;
  Future<void>? _stopPending;
  bool _cancelRequested = false;

  bool get canCancel => progress.phase == LibraryUpdatePhase.scanning;

  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    _setPhase(LibraryUpdatePhase.cancelling);
    _stopPending = Future<void>.sync(() async => stopScan?.call()).catchError(
      (Object error) {
        // Even if native cancellation cannot be signalled, never publish staging.
        debugPrint('[library scan cancellation] $error');
      },
    );
    await _stopPending;
  }

  Future<void> update() {
    final current = _activeUpdate;
    if (current != null) return current;
    final next = Future<void>.microtask(_runUpdate);
    _activeUpdate = next;
    return next.whenComplete(() {
      if (identical(_activeUpdate, next)) _activeUpdate = null;
    });
  }

  Future<void> _runUpdate() async {
    _cancelRequested = false;
    _stopPending = null;
    progress = const LibraryUpdateProgress(phase: LibraryUpdatePhase.scanning);
    notifyListeners();
    try {
      await for (final action in await scan()) {
        if (!_cancelRequested) {
          progress = LibraryUpdateProgress(
              action: action, phase: LibraryUpdatePhase.scanning);
          notifyListeners();
        }
      }
      if (_cancelRequested) {
        _setPhase(LibraryUpdatePhase.cancelled);
        return;
      }
      _setPhase(LibraryUpdatePhase.publishing);
      await reloadLibrary();
      _setPhase(LibraryUpdatePhase.reconciling);
      await reconcileAppData();
      _setPhase(LibraryUpdatePhase.lyrics);
      await refreshLyrics();
      _setPhase(LibraryUpdatePhase.completed);
    } catch (error) {
      if (_cancelRequested) {
        _setPhase(LibraryUpdatePhase.cancelled);
        return;
      }
      _setPhase(LibraryUpdatePhase.failed, error: error);
      rethrow;
    } finally {
      try {
        await _stopPending;
        await cleanUp?.call();
      } on FileSystemException catch (error) {
        debugPrint('[library scan cleanup] $error');
      }
    }
  }

  void _setPhase(LibraryUpdatePhase phase, {Object? error}) {
    progress = LibraryUpdateProgress(
        action: progress.action, phase: phase, error: error);
    notifyListeners();
  }
}
