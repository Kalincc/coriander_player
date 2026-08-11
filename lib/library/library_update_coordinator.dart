import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/foundation.dart';

@immutable
class LibraryUpdateProgress {
  const LibraryUpdateProgress({
    this.action,
    this.isUpdating = false,
    this.error,
  });

  final IndexActionState? action;
  final bool isUpdating;
  final Object? error;
}

class LibraryUpdateCoordinator extends ChangeNotifier {
  LibraryUpdateCoordinator({
    required this.scan,
    required this.reloadLibrary,
    required this.refreshLyrics,
    required this.reconcileAppData,
  });

  final Future<Stream<IndexActionState>> Function() scan;
  final Future<void> Function() reloadLibrary;
  final Future<void> Function() refreshLyrics;
  final Future<void> Function() reconcileAppData;

  LibraryUpdateProgress progress = const LibraryUpdateProgress();
  Future<void>? _activeUpdate;

  Future<void> update() {
    final current = _activeUpdate;
    if (current != null) return current;
    final next = _runUpdate();
    _activeUpdate = next;
    return next.whenComplete(() {
      if (identical(_activeUpdate, next)) _activeUpdate = null;
    });
  }

  Future<void> _runUpdate() async {
    progress = const LibraryUpdateProgress(isUpdating: true);
    notifyListeners();
    try {
      await for (final action in await scan()) {
        progress = LibraryUpdateProgress(action: action, isUpdating: true);
        notifyListeners();
      }
      await reloadLibrary();
      await reconcileAppData();
      await refreshLyrics();
      progress = LibraryUpdateProgress(action: progress.action);
      notifyListeners();
    } catch (error) {
      progress = LibraryUpdateProgress(action: progress.action, error: error);
      notifyListeners();
      rethrow;
    }
  }
}
