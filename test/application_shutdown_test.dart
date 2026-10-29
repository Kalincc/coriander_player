import 'dart:async';

import 'package:coriander_player/application_shutdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production shutdown is shared by normal and update exits', () {
    expect(ApplicationShutdown.production(),
        same(ApplicationShutdown.production()));
  });

  test('saves before closing resources', () async {
    final events = <String>[];
    final shutdown = shutdownFixture(events);

    await shutdown.exitNormally();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('does not close resources when saving fails', () async {
    final events = <String>[];
    final shutdown = ApplicationShutdown(
      savePlaylists: () async => events.add('playlists'),
      saveLyricSources: () async {
        events.add('lyrics');
        throw StateError('disk full');
      },
      saveSettings: () async => events.add('settings'),
      savePreferences: () async => events.add('preferences'),
      closePlayback: () => events.add('playback'),
      unregisterHotkeys: () async => events.add('hotkeys'),
      closeWindow: () async => events.add('window'),
    );

    await expectLater(shutdown.exitNormally(), throwsA(isA<StateError>()));
    expect(events, ['playlists', 'lyrics']);
  });

  test('can close after a successful update handoff', () async {
    final events = <String>[];
    final shutdown = shutdownFixture(events);

    await shutdown.saveUserState();
    await shutdown.closeAfterUpdateHandoff();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('concurrent and later close requests save and release only once',
      () async {
    final events = <String>[];
    final saved = Completer<void>();
    final shutdown = shutdownFixture(events, savePlaylists: () async {
      events.add('playlists');
      await saved.future;
    });

    final first = shutdown.exitNormally();
    final second = shutdown.exitNormally();
    expect(events, ['playlists']);
    saved.complete();
    await Future.wait([first, second]);
    await shutdown.exitNormally();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('a failed save can be retried without releasing resources early',
      () async {
    final events = <String>[];
    var fail = true;
    final shutdown = shutdownFixture(events, savePlaylists: () async {
      events.add('playlists');
      if (fail) throw StateError('disk full');
    });

    await expectLater(shutdown.exitNormally(), throwsStateError);
    expect(events, ['playlists']);
    fail = false;
    await shutdown.exitNormally();
    await shutdown.exitNormally();

    expect(events, [
      'playlists',
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('normal close after update handoff does not save or release again',
      () async {
    final events = <String>[];
    final shutdown = shutdownFixture(events);

    await shutdown.saveUserState();
    await shutdown.closeAfterUpdateHandoff();
    await shutdown.exitNormally();
    await shutdown.closeAfterUpdateHandoff();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('waits for playback state before saving and releasing resources',
      () async {
    final events = <String>[];
    final prepared = Completer<void>();
    final shutdown = shutdownFixture(events, preparePlaybackShutdown: () async {
      events.add('prepare');
      await prepared.future;
    });

    final exiting = shutdown.exitNormally();
    expect(events, ['prepare']);
    prepared.complete();
    await exiting;

    expect(events, [
      'prepare',
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('playback preparation failure does not exit and can be retried',
      () async {
    final events = <String>[];
    var fail = true;
    final shutdown = shutdownFixture(events, preparePlaybackShutdown: () {
      events.add('prepare');
      if (fail) throw StateError('history save failed');
      return Future.value();
    });

    await expectLater(shutdown.exitNormally(), throwsStateError);
    expect(events, ['prepare']);
    fail = false;
    await shutdown.exitNormally();
    expect(events, [
      'prepare',
      'prepare',
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('a later save still persists changes after an abandoned update',
      () async {
    final events = <String>[];
    final shutdown = shutdownFixture(events);

    await shutdown.saveUserState();
    events.clear();
    await shutdown.exitNormally();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('resource retry does not release playback twice', () async {
    final events = <String>[];
    var fail = true;
    final shutdown = shutdownFixture(
      events,
      preparePlaybackShutdown: () async => events.add('prepare'),
      unregisterHotkeys: () async {
        events.add('hotkeys');
        if (fail) throw StateError('hotkey failure');
      },
    );

    await expectLater(shutdown.exitNormally(), throwsStateError);
    fail = false;
    await shutdown.exitNormally();

    expect(events.where((event) => event == 'playback'), hasLength(1));
    expect(events.where((event) => event == 'prepare'), hasLength(1));
    expect(events.where((event) => event == 'window'), hasLength(1));
  });

  test('normal close during update resource cleanup does not save again',
      () async {
    final events = <String>[];
    final unregistered = Completer<void>();
    final shutdown = shutdownFixture(events, unregisterHotkeys: () async {
      events.add('hotkeys');
      await unregistered.future;
    });

    await shutdown.saveUserState();
    final handoff = shutdown.closeAfterUpdateHandoff();
    final nativeClose = shutdown.exitNormally();
    unregistered.complete();
    await Future.wait([handoff, nativeClose]);

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('update cleanup waits for a pending save', () async {
    final events = <String>[];
    final saved = Completer<void>();
    final shutdown = shutdownFixture(events, savePlaylists: () async {
      events.add('playlists');
      await saved.future;
    });

    final saving = shutdown.saveUserState();
    final closing = shutdown.closeAfterUpdateHandoff();
    expect(events, ['playlists']);
    saved.complete();
    await Future.wait([saving, closing]);

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  test('closing before initialization skips persistence and closes only once',
      () async {
    final events = <String>[];
    final shutdown = shutdownFixture(
      events,
      userStateLoaded: false,
      preparePlaybackShutdown: () async => events.add('prepare'),
    );

    await Future.wait([shutdown.exitNormally(), shutdown.exitNormally()]);
    await shutdown.exitNormally();

    expect(events, ['playback', 'hotkeys', 'window']);
  });

  test('marking initialization complete enables a later save', () async {
    final events = <String>[];
    final shutdown = shutdownFixture(
      events,
      userStateLoaded: false,
      preparePlaybackShutdown: () async => events.add('prepare'),
    );

    await shutdown.saveUserState();
    expect(events, isEmpty);
    shutdown.markUserStateLoaded();
    shutdown.markUserStateLoaded();
    await shutdown.exitNormally();

    expect(events, [
      'prepare',
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });
}

ApplicationShutdown shutdownFixture(
  List<String> events, {
  Future<void> Function()? savePlaylists,
  Future<void> Function()? preparePlaybackShutdown,
  Future<void> Function()? unregisterHotkeys,
  Future<void> Function()? closeWindow,
  bool userStateLoaded = true,
}) {
  return ApplicationShutdown(
    savePlaylists: savePlaylists ?? () async => events.add('playlists'),
    saveLyricSources: () async => events.add('lyrics'),
    saveSettings: () async => events.add('settings'),
    savePreferences: () async => events.add('preferences'),
    closePlayback: () => events.add('playback'),
    preparePlaybackShutdown: preparePlaybackShutdown,
    unregisterHotkeys: unregisterHotkeys ?? () async => events.add('hotkeys'),
    closeWindow: closeWindow ?? () async => events.add('window'),
    userStateLoaded: userStateLoaded,
  );
}
