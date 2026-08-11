import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/play_service/desktop_lyric_service.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/play_service/playback_queue_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';

class PlaybackDataInitializer {
  PlaybackDataInitializer({
    required this.loadQueue,
    required this.loadHistory,
  });

  final Future<void> Function(Iterable<Audio> library) loadQueue;
  final Future<void> Function() loadHistory;

  Future<void> initialize(Iterable<Audio> library) async {
    await loadQueue(library);
    await loadHistory();
  }
}

class PlaybackDataReconciler {
  PlaybackDataReconciler({
    required this.reconcileQueue,
    required this.reconcileHistory,
  });

  final Future<void> Function(Iterable<Audio> library) reconcileQueue;
  final Future<void> Function(Iterable<Audio> library) reconcileHistory;

  Future<void> reconcile(Iterable<Audio> library) async {
    final snapshot = List<Audio>.from(library);
    await reconcileQueue(snapshot);
    await reconcileHistory(snapshot);
  }
}

class PlayService {
  late final playbackService = PlaybackService(this);
  late final lyricService = LyricService(this);
  late final desktopLyricService = DesktopLyricService(this);
  late final Future<PlaybackQueueService> _playbackQueueService =
      _createPlaybackQueueService();
  late final Future<PlaybackHistoryService> _playbackHistoryService =
      _createPlaybackHistoryService();

  PlaybackQueueService? _loadedPlaybackQueueService;
  PlaybackQueueService? get playbackQueueService => _loadedPlaybackQueueService;
  PlaybackHistoryService? _loadedPlaybackHistoryService;
  PlaybackHistoryService? get playbackHistoryService =>
      _loadedPlaybackHistoryService;

  PlayService._();

  static PlayService? _instance;
  static PlayService get instance {
    _instance ??= PlayService._();
    return _instance!;
  }

  Future<void> loadPlaybackQueue(Iterable<Audio> library) async {
    final queueService = await _playbackQueueService;
    await queueService.load(library);
    _loadedPlaybackQueueService = queueService;
    playbackService.attachQueue(queueService);
  }

  Future<void> loadPlaybackHistory() async {
    final historyService = await _playbackHistoryService;
    await historyService.load();
    _loadedPlaybackHistoryService = historyService;
    playbackService.attachHistory(historyService);
  }

  Future<void> initializePlaybackData(Iterable<Audio> library) async {
    await PlaybackDataInitializer(
      loadQueue: loadPlaybackQueue,
      loadHistory: loadPlaybackHistory,
    ).initialize(library);
  }

  Future<void> reconcilePlaybackData(Iterable<Audio> library) async {
    final snapshot = List<Audio>.from(library);
    if (_loadedPlaybackQueueService == null ||
        _loadedPlaybackHistoryService == null) {
      await initializePlaybackData(snapshot);
    }
    final queue = _loadedPlaybackQueueService;
    final history = _loadedPlaybackHistoryService;
    if (queue != null && history != null) {
      await PlaybackDataReconciler(
        reconcileQueue: queue.reconcile,
        reconcileHistory: history.reconcileLibrary,
      ).reconcile(snapshot);
    }
    await reconcilePlaylistAudios(snapshot);
  }

  Future<PlaybackQueueService> _createPlaybackQueueService() async {
    final directory = await getAppDataDir();
    return PlaybackQueueService(store: LocalJsonStore(directory));
  }

  Future<PlaybackHistoryService> _createPlaybackHistoryService() async {
    final directory = await getAppDataDir();
    return PlaybackHistoryService(store: LocalJsonStore(directory));
  }

  void close() {
    desktopLyricService.killDesktopLyric();
    playbackService.close();
  }
}
