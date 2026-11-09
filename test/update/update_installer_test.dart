import 'dart:async';
import 'dart:io';

import 'package:coriander_player/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File helper;
  late File installer;
  late File log;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('handoff-startup-');
    addTearDown(() => directory.delete(recursive: true));
    helper = await File('${directory.path}/bundled-helper.exe')
        .writeAsString('test helper');
    installer = File('${directory.path}/update.Setup.exe');
    log = File('${directory.path}/update.Install.log');
  });

  test('stages a separate helper with the parent pid and verified paths',
      () async {
    String? executable;
    List<String>? arguments;
    final updater = UpdateInstaller(
      helper: helper,
      startDetached: (path, args) async {
        executable = path;
        arguments = args;
        return 123;
      },
      confirmStartup: (pid, log) async => expect(pid, 123),
    );

    await updater.start(installer: installer, log: log);

    expect(File(executable!).uri.pathSegments.last, updateHandoffExecutable);
    expect(await File(executable!).readAsString(), 'test helper');
    expect(arguments, ['$pid', installer.absolute.path, log.absolute.path]);
    expect(await log.exists(), isFalse);
  });

  test('propagates installer launch failures', () async {
    final updater = UpdateInstaller(
      helper: helper,
      startDetached: (path, args) async {
        throw StateError('cannot start');
      },
    );

    await expectLater(
      updater.start(
        installer: installer,
        log: log,
      ),
      throwsA(isA<UpdateInstallerException>()),
    );
  });

  test('a created process is not a confirmed helper handoff', () async {
    final ready = Completer<void>();
    final spawned = Completer<void>();
    var started = false;
    final updater = UpdateInstaller(
      helper: helper,
      startDetached: (_, __) async {
        spawned.complete();
        return 123;
      },
      confirmStartup: (_, __) => ready.future,
    );
    final launch = updater
        .start(
          installer: installer,
          log: log,
        )
        .then((_) => started = true);
    await spawned.future;
    expect(started, isFalse);
    ready.complete();
    await launch;
    expect(started, isTrue);
  });

  test('an old log cannot falsely acknowledge a new installer', () async {
    await log.writeAsString('previous failure evidence');
    var launched = false;
    final updater = UpdateInstaller(
      startDetached: (_, __) async {
        launched = true;
        return 123;
      },
      confirmStartup: (_, __) async {},
    );
    await expectLater(updater.start(installer: File('installer.exe'), log: log),
        throwsA(isA<UpdateInstallerException>()));
    expect(launched, isFalse);
    expect(await log.readAsString(), 'previous failure evidence');
  });

  test(
      'handoff requires a nonempty acknowledgement and catches an immediate exit',
      () async {
    await handoffReadyFile(log).writeAsString('ready');
    await expectLater(
      waitForHandoffReady(
        log: log,
        readExitCode: () => 7,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<UpdateInstallerException>()
          .having((error) => error.exitCode, 'exitCode', 7)),
    );
    await waitForHandoffReady(
      log: log,
      readExitCode: () => null,
    );
  });

  test('an alive helper without acknowledgement cannot close the player',
      () async {
    await log.writeAsString('installer log is not a handoff acknowledgement');
    await expectLater(
      waitForHandoffReady(
        log: log,
        readExitCode: () => null,
        timeout: const Duration(milliseconds: 25),
        pollInterval: const Duration(milliseconds: 2),
      ),
      throwsA(isA<UpdateInstallerException>().having(
          (error) => error.processMayBeRunning, 'may be running', true)),
    );
  });

  test('failed acknowledgement cancels the pending handoff', () async {
    final updater = UpdateInstaller(
      helper: helper,
      startDetached: (_, __) async => 123,
      confirmStartup: (_, __) async => throw StateError('not ready'),
    );
    await expectLater(
      updater.start(installer: installer, log: log),
      throwsA(isA<UpdateInstallerException>()),
    );
    expect(await handoffCancelFile(log).exists(), isTrue);
  });
}
