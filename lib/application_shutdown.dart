import 'dart:async';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/playlist.dart' as playlist;
import 'package:coriander_player/lyric/lyric_source.dart' as lyric;
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/runtime_diagnostic_log.dart';
import 'package:coriander_player/utils.dart';
import 'package:window_manager/window_manager.dart';

class ApplicationShutdown with WindowListener {
  ApplicationShutdown({
    required this.savePlaylists,
    required this.saveLyricSources,
    required this.saveSettings,
    required this.savePreferences,
    required this.closePlayback,
    required this.unregisterHotkeys,
    required this.closeWindow,
    this.preparePlaybackShutdown,
    this.recordDiagnostics,
    bool userStateLoaded = true,
  }) : _userStateLoaded = userStateLoaded;

  factory ApplicationShutdown.production() => _production;

  static final _production = ApplicationShutdown(
    savePlaylists: () => playlist.savePlaylists(rethrowOnError: true),
    saveLyricSources: () => lyric.saveLyricSources(rethrowOnError: true),
    saveSettings: () => AppSettings.instance.saveSettings(rethrowOnError: true),
    savePreferences: () => AppPreference.instance.save(rethrowOnError: true),
    preparePlaybackShutdown: () =>
        PlayService.instance.playbackService.prepareForShutdown(),
    closePlayback: () => PlayService.instance.close(),
    unregisterHotkeys: HotkeysHelper.unregisterAll,
    recordDiagnostics: RuntimeDiagnosticLog.instance.record,
    // close() sends WM_CLOSE again; destroy() ends the intercepted close.
    closeWindow: windowManager.destroy,
    userStateLoaded: false,
  );

  final Future<void> Function() savePlaylists;
  final Future<void> Function() saveLyricSources;
  final Future<void> Function() saveSettings;
  final Future<void> Function() savePreferences;
  final void Function() closePlayback;
  final Future<void> Function() unregisterHotkeys;
  final Future<void> Function() closeWindow;
  final Future<void> Function()? preparePlaybackShutdown;
  final Future<void> Function(String message)? recordDiagnostics;
  final _timings = <String, int>{};

  Future<void>? _saving;
  Future<void>? _exiting;
  Future<void>? _closing;
  bool _playbackClosed = false;
  bool _hotkeysUnregistered = false;
  bool _userStateLoaded;

  void markUserStateLoaded() {
    _userStateLoaded = true;
  }

  Future<void> listenForWindowClose() async {
    if (windowManager.listeners.contains(this)) return;
    windowManager.addListener(this);
    try {
      await windowManager.setPreventClose(true);
    } catch (_) {
      windowManager.removeListener(this);
      rethrow;
    }
  }

  @override
  void onWindowClose() async {
    try {
      await exitNormally();
    } catch (error, stackTrace) {
      LOGGER.e(error, stackTrace: stackTrace);
      showTextOnSnackBar('保存数据失败，播放器未退出。');
    }
  }

  Future<void> saveUserState() => _saving ??= _saveUserState().whenComplete(() {
        // An update may fail before handoff; a later exit must save new changes.
        _saving = null;
      });

  Future<void> _saveUserState() async {
    _timings.clear();
    // Before startup finishes, empty globals must not overwrite saved data.
    if (!_userStateLoaded) return;
    if (preparePlaybackShutdown != null) {
      await _timed('history', preparePlaybackShutdown!);
    }
    // Different files are independent. Wait for every write even if one fails,
    // so a retry never races a write that the first attempt left running.
    await Future.wait([
      _timed('playlists', savePlaylists),
      _timed('lyric sources', saveLyricSources),
      _timed('settings', saveSettings),
      _timed('preferences', savePreferences),
    ]);
  }

  Future<void> _timed(String stage, FutureOr<void> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      await action();
    } finally {
      _timings[stage] = watch.elapsedMilliseconds;
      LOGGER.i('[shutdown] $stage: ${watch.elapsedMilliseconds} ms');
    }
  }

  Future<void> closeAfterUpdateHandoff() => _closing ??= _closeResources();

  Future<void> _closeResources() async {
    try {
      await _saving;
      if (!_playbackClosed) {
        await _timed('audio resources', closePlayback);
        _playbackClosed = true;
      }
      if (!_hotkeysUnregistered) {
        await _timed('hotkeys', unregisterHotkeys);
        _hotkeysUnregistered = true;
      }
      await _writeTimings('ready to close');
      await closeWindow();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }

  Future<void> _writeTimings(String outcome) async {
    if (recordDiagnostics == null) return;
    try {
      // Nonessential diagnostics may never turn an I/O fault into a long exit.
      await recordDiagnostics!('[shutdown] $outcome; $_timings')
          .timeout(const Duration(milliseconds: 100));
    } catch (error) {
      LOGGER.w('[shutdown diagnostics] $error');
    }
  }

  Future<void> exitNormally() => _closing ?? (_exiting ??= _exitNormally());

  Future<void> _exitNormally() async {
    try {
      if (!_playbackClosed) await saveUserState();
      await closeAfterUpdateHandoff();
    } catch (_) {
      await _writeTimings('failed; window retained');
      _exiting = null;
      rethrow;
    }
  }
}
