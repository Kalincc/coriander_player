import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/play_service/desktop_lyric_service.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/play_service/playback_service.dart';

class PlaybackDataInitializer {
  PlaybackDataInitializer({
    required this.loadHistory,
  });

  final Future<void> Function() loadHistory;

  Future<void> initialize(Iterable<Audio> library) async {
    await loadHistory();
  }
}

class PlaybackDataReconciler {
  PlaybackDataReconciler({
    required this.reconcileHistory,
  });

  final Future<void> Function(Iterable<Audio> library) reconcileHistory;

  Future<void> reconcile(Iterable<Audio> library) async {
    final snapshot = List<Audio>.from(library);
    await reconcileHistory(snapshot);
  }
}

class PlayService {
  late final playbackService = PlaybackService(this);
  late final lyricService = LyricService(this);
  late final desktopLyricService = DesktopLyricService(this);
  late final Future<PlaybackHistoryService> _playbackHistoryService =
      _createPlaybackHistoryService();

  PlaybackHistoryService? _loadedPlaybackHistoryService;
  PlaybackHistoryService? get playbackHistoryService =>
      _loadedPlaybackHistoryService;

  PlayService._();

  static PlayService? _instance;
  static PlayService get instance {
    _instance ??= PlayService._();
    return _instance!;
  }

  Future<void> loadPlaybackHistory() async {
    final historyService = await _playbackHistoryService;
    await historyService.load();
    _loadedPlaybackHistoryService = historyService;
    playbackService.attachHistory(historyService);
  }

  Future<void> initializePlaybackData(Iterable<Audio> library) async {
    await PlaybackDataInitializer(
      loadHistory: loadPlaybackHistory,
    ).initialize(library);
  }

  Future<void> reconcilePlaybackData(Iterable<Audio> library) async {
    final snapshot = List<Audio>.from(library);
    if (_loadedPlaybackHistoryService == null) {
      await initializePlaybackData(snapshot);
    }
    final history = _loadedPlaybackHistoryService;
    if (history != null) {
      await PlaybackDataReconciler(
        reconcileHistory: history.reconcileLibrary,
      ).reconcile(snapshot);
    }
    await reconcilePlaylistAudios(snapshot);
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
