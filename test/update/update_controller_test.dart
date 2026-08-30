import 'dart:async';
import 'dart:io';

import 'package:coriander_player/application_shutdown.dart';
import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/update/install_environment.dart';
import 'package:coriander_player/update/update_controller.dart';
import 'package:coriander_player/update/update_downloader.dart';
import 'package:coriander_player/update/update_installer.dart';
import 'package:coriander_player/update/update_release.dart';
import 'package:coriander_player/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installed update saves launches then closes in order', () async {
    final events = <String>[];
    final controller = controllerFixture(installed: true, events: events);

    await controller.check();
    await controller.install();

    expect(events, [
      'check',
      'download',
      'verify',
      'save',
      'launch',
      'close',
    ]);
    expect(controller.state, isA<UpdatePreparingInstall>());
    controller.dispose();
  });

  test('installer launch failure leaves player open', () async {
    final events = <String>[];
    final controller = controllerFixture(
      installed: true,
      events: events,
      launchError: StateError('cannot start'),
    );

    await controller.check();
    await controller.install();

    expect(controller.state, isA<UpdateFailed>());
    expect(events, isNot(contains('close')));
    controller.dispose();
  });

  test('save failure prevents installer launch and close', () async {
    final events = <String>[];
    final controller = controllerFixture(
      installed: true,
      events: events,
      saveError: StateError('disk full'),
    );

    await controller.check();
    await controller.install();

    expect(controller.state, isA<UpdateFailed>());
    expect(events, isNot(contains('launch')));
    expect(events, isNot(contains('close')));
    controller.dispose();
  });

  test('portable editions do not create a download or install automatically',
      () async {
    final events = <String>[];
    final controller = controllerFixture(installed: false, events: events);

    await controller.check();
    expect(
      (controller.state as UpdateAvailable).canAutoInstall,
      isFalse,
    );
    await controller.install();

    expect(events, ['check']);
    controller.dispose();
  });

  test('reports that the current version is up to date', () async {
    final events = <String>[];
    final controller = controllerFixture(
      installed: true,
      events: events,
      noUpdate: true,
    );

    await controller.check();

    expect(controller.state, isA<UpdateCurrent>());
    expect(events, ['check']);
    controller.dispose();
  });

  test('ignores a duplicate check while one is active', () async {
    final events = <String>[];
    final checking = Completer<void>();
    final service = _FakeService(_candidate, events, gate: checking);
    final controller = _controllerWith(
      service: service,
      environment: _installedEnvironment(),
      downloader: _FakeDownloader(events, _successfulDownload),
      installer: _FakeInstaller(events, null),
      shutdown: _FakeShutdown(events, null),
    );

    final first = controller.check();
    final second = controller.check();
    checking.complete();
    await Future.wait([first, second]);

    expect(events, ['check']);
    controller.dispose();
  });

  test('hash failures stop before saving or launching', () async {
    final events = <String>[];
    final controller = controllerFixture(
      installed: true,
      events: events,
      download: (candidate, directory, cancellation, onProgress) async {
        throw const UpdateHashMismatchException(expected: 'a', actual: 'b');
      },
    );

    await controller.check();
    await controller.install();

    expect(controller.state, isA<UpdateFailed>());
    expect(events, ['check', 'download']);
    controller.dispose();
  });

  test('cancelling an active download reports a cancelled state', () async {
    final events = <String>[];
    final downloadStarted = Completer<void>();
    final controller = controllerFixture(
      installed: true,
      events: events,
      download: (candidate, directory, cancellation, onProgress) async {
        downloadStarted.complete();
        onProgress(const UpdateDownloadProgress(
          phase: UpdateDownloadPhase.downloading,
          receivedBytes: 0,
          totalBytes: 1,
        ));
        while (!cancellation.isCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        throw const UpdateCancelledException();
      },
    );

    await controller.check();
    final installFuture = controller.install();
    await downloadStarted.future;
    controller.cancelDownload();
    await installFuture;

    expect(controller.state, isA<UpdateCancelled>());
    expect(events, ['check', 'download']);
    controller.dispose();
  });
}

final _candidate = UpdateCandidate(
  version: ForkReleaseVersion.parse('1.5.1-kalin.10'),
  releaseName: 'Coriander Player 1.5.1-kalin.10',
  releaseNotes: 'notes',
  publishedAt: null,
  releasePageUri: Uri.parse(
    'https://github.com/Kalincc/coriander_player/releases/tag/v1.5.1-kalin.10',
  ),
  installerFileName: 'Coriander.Player.1.5.1-kalin.10.Setup.exe',
  installerUri: Uri.parse('https://example.com/installer.exe'),
  checksumUri: Uri.parse('https://example.com/SHA256SUMS.txt'),
);

UpdateController controllerFixture({
  required bool installed,
  required List<String> events,
  UpdateCandidate? candidate,
  bool noUpdate = false,
  Object? saveError,
  Object? launchError,
  Future<VerifiedUpdate> Function(
    UpdateCandidate candidate,
    Directory directory,
    UpdateCancellation cancellation,
    void Function(UpdateDownloadProgress progress) onProgress,
  )? download,
}) {
  final service =
      _FakeService(noUpdate ? null : candidate ?? _candidate, events);
  final environment = InstallEnvironment(
    readInstallLocation: () => r'C:\Apps\Coriander Player',
    executablePath: () => installed
        ? r'C:\Apps\Coriander Player\coriander_player.exe'
        : r'C:\Portable\coriander_player.exe',
    isWindows: () => true,
  );
  final downloader = _FakeDownloader(
    events,
    download ??
        (candidate, directory, cancellation, onProgress) async {
          onProgress(const UpdateDownloadProgress(
            phase: UpdateDownloadPhase.downloading,
            receivedBytes: 1,
            totalBytes: 1,
          ));
          onProgress(const UpdateDownloadProgress(
            phase: UpdateDownloadPhase.verifying,
            receivedBytes: 1,
            totalBytes: 1,
          ));
          events.add('verify');
          return VerifiedUpdate(
            installer: File('installer.exe'),
            installLog: File('install.log'),
          );
        },
  );
  final installer = _FakeInstaller(events, launchError);
  final shutdown = _FakeShutdown(events, saveError);
  return UpdateController(
    service: service,
    environment: environment,
    downloader: downloader,
    installer: installer,
    shutdown: shutdown,
    createTemporaryDirectory: () async => Directory.systemTemp.createTemp(
      'coriander-controller-test-',
    ),
  );
}

UpdateController _controllerWith({
  required UpdateService service,
  required InstallEnvironment environment,
  required UpdateDownloader downloader,
  required UpdateInstaller installer,
  required ApplicationShutdown shutdown,
}) {
  return UpdateController(
    service: service,
    environment: environment,
    downloader: downloader,
    installer: installer,
    shutdown: shutdown,
    createTemporaryDirectory: () async => Directory.systemTemp.createTemp(
      'coriander-controller-test-',
    ),
  );
}

InstallEnvironment _installedEnvironment() {
  return InstallEnvironment(
    readInstallLocation: () => r'C:\Apps\Coriander Player',
    executablePath: () => r'C:\Apps\Coriander Player\coriander_player.exe',
    isWindows: () => true,
  );
}

Future<VerifiedUpdate> _successfulDownload(
  UpdateCandidate candidate,
  Directory directory,
  UpdateCancellation cancellation,
  void Function(UpdateDownloadProgress progress) onProgress,
) async {
  onProgress(const UpdateDownloadProgress(
    phase: UpdateDownloadPhase.downloading,
    receivedBytes: 1,
    totalBytes: 1,
  ));
  onProgress(const UpdateDownloadProgress(
    phase: UpdateDownloadPhase.verifying,
    receivedBytes: 1,
    totalBytes: 1,
  ));
  return VerifiedUpdate(
    installer: File('installer.exe'),
    installLog: File('install.log'),
  );
}

class _FakeService extends UpdateService {
  _FakeService(this.candidate, this.events, {this.gate})
      : super(releases: () => const Stream<Never>.empty());

  final UpdateCandidate? candidate;
  final List<String> events;
  final Completer<void>? gate;

  @override
  Future<UpdateCandidate?> check(_) async {
    events.add('check');
    await gate?.future;
    return candidate;
  }
}

class _FakeDownloader extends UpdateDownloader {
  _FakeDownloader(this.events, this.action);

  final List<String> events;
  final Future<VerifiedUpdate> Function(
    UpdateCandidate candidate,
    Directory directory,
    UpdateCancellation cancellation,
    void Function(UpdateDownloadProgress progress) onProgress,
  ) action;

  @override
  Future<VerifiedUpdate> downloadAndVerify(
    UpdateCandidate candidate,
    Directory temporaryDirectory, {
    required UpdateCancellation cancellation,
    required void Function(UpdateDownloadProgress progress) onProgress,
  }) {
    events.add('download');
    return action(candidate, temporaryDirectory, cancellation, onProgress);
  }
}

class _FakeInstaller extends UpdateInstaller {
  _FakeInstaller(this.events, this.error)
      : super(startDetached: (_, __) async {});

  final List<String> events;
  final Object? error;

  @override
  Future<void> start({required File installer, required File log}) async {
    events.add('launch');
    if (error != null) throw error!;
  }
}

class _FakeShutdown extends ApplicationShutdown {
  _FakeShutdown(this.events, this.saveError)
      : super(
          savePlaylists: () async {},
          saveLyricSources: () async {},
          saveSettings: () async {},
          savePreferences: () async {},
          closePlayback: () {},
          unregisterHotkeys: () async {},
          closeWindow: () async {},
        );

  final List<String> events;
  final Object? saveError;

  @override
  Future<void> saveUserState() async {
    events.add('save');
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> closeAfterUpdateHandoff() async {
    events.add('close');
  }
}
