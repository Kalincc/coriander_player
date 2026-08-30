import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/playlist.dart' as playlist;
import 'package:coriander_player/lyric/lyric_source.dart' as lyric;
import 'package:coriander_player/play_service/play_service.dart';
import 'package:window_manager/window_manager.dart';

class ApplicationShutdown {
  ApplicationShutdown({
    required this.savePlaylists,
    required this.saveLyricSources,
    required this.saveSettings,
    required this.savePreferences,
    required this.closePlayback,
    required this.unregisterHotkeys,
    required this.closeWindow,
  });

  factory ApplicationShutdown.production() {
    return ApplicationShutdown(
      savePlaylists: () => playlist.savePlaylists(rethrowOnError: true),
      saveLyricSources: () => lyric.saveLyricSources(rethrowOnError: true),
      saveSettings: () =>
          AppSettings.instance.saveSettings(rethrowOnError: true),
      savePreferences: () => AppPreference.instance.save(rethrowOnError: true),
      closePlayback: PlayService.instance.close,
      unregisterHotkeys: HotkeysHelper.unregisterAll,
      closeWindow: windowManager.close,
    );
  }

  final Future<void> Function() savePlaylists;
  final Future<void> Function() saveLyricSources;
  final Future<void> Function() saveSettings;
  final Future<void> Function() savePreferences;
  final void Function() closePlayback;
  final Future<void> Function() unregisterHotkeys;
  final Future<void> Function() closeWindow;

  Future<void> saveUserState() async {
    await savePlaylists();
    await saveLyricSources();
    await saveSettings();
    await savePreferences();
  }

  Future<void> closeAfterUpdateHandoff() async {
    closePlayback();
    await unregisterHotkeys();
    await closeWindow();
  }

  Future<void> exitNormally() async {
    await saveUserState();
    await closeAfterUpdateHandoff();
  }
}
