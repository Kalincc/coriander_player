import 'package:coriander_player/application_shutdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

ApplicationShutdown shutdownFixture(List<String> events) {
  return ApplicationShutdown(
    savePlaylists: () async => events.add('playlists'),
    saveLyricSources: () async => events.add('lyrics'),
    saveSettings: () async => events.add('settings'),
    savePreferences: () async => events.add('preferences'),
    closePlayback: () => events.add('playback'),
    unregisterHotkeys: () async => events.add('hotkeys'),
    closeWindow: () async => events.add('window'),
  );
}
