import 'dart:async';
import 'dart:io';

import 'package:coriander_player/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launches the installer with silent update arguments', () async {
    String? executable;
    List<String>? arguments;
    final updater = UpdateInstaller(
      startDetached: (path, args) async {
        executable = path;
        arguments = args;
        return 123;
      },
      confirmStartup: (pid, log) async => expect(pid, 123),
    );

    await updater.start(
      installer: File(r'C:\Temp\Coriander.Setup.exe'),
      log: File(r'C:\Temp\Coriander.Install.log'),
    );

    expect(executable, r'C:\Temp\Coriander.Setup.exe');
    expect(
        arguments,
        containsAll([
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
          '/CORIANDERAPPUPDATE=1',
          r'/LOG=C:\Temp\Coriander.Install.log',
        ]));
  });

  test('propagates installer launch failures', () async {
    final updater = UpdateInstaller(
      startDetached: (path, args) async {
        throw StateError('cannot start');
      },
    );

    await expectLater(
      updater.start(
        installer: File(r'C:\Temp\Coriander.Setup.exe'),
        log: File(r'C:\Temp\Coriander.Install.log'),
      ),
      throwsA(isA<UpdateInstallerException>()),
    );
  });

  test('a created process is not a confirmed installer startup', () async {
    final ready = Completer<void>();
    var started = false;
    final updater = UpdateInstaller(
      startDetached: (_, __) async => 123,
      confirmStartup: (_, __) => ready.future,
    );
    final launch = updater
        .start(
          installer: File('installer.exe'),
          log: File('not-created-install.log'),
        )
        .then((_) => started = true);
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);
    ready.complete();
    await launch;
    expect(started, isTrue);
  });

  test('an old log cannot falsely acknowledge a new installer', () async {
    final directory =
        await Directory.systemTemp.createTemp('installer-startup-');
    addTearDown(() => directory.delete(recursive: true));
    final log = File('${directory.path}/install.log');
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

  test('startup requires a nonempty log and catches an immediate exit',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('installer-startup-');
    addTearDown(() => directory.delete(recursive: true));
    final log = File('${directory.path}/install.log');
    await log.writeAsString('startup log');
    await expectLater(
      waitForInstallerStartup(
        log: log,
        readExitCode: () => 7,
        timeout: const Duration(milliseconds: 50),
        settleTime: Duration.zero,
      ),
      throwsA(isA<UpdateInstallerException>()
          .having((error) => error.exitCode, 'exitCode', 7)),
    );
    await waitForInstallerStartup(
      log: log,
      readExitCode: () => null,
      settleTime: Duration.zero,
    );
  });

  test('an alive process without a log times out without a successful handoff',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('installer-startup-');
    addTearDown(() => directory.delete(recursive: true));
    final log = File('${directory.path}/install.log');
    await log.writeAsString('');
    await expectLater(
      waitForInstallerStartup(
        log: log,
        readExitCode: () => null,
        timeout: const Duration(milliseconds: 25),
        pollInterval: const Duration(milliseconds: 2),
        settleTime: Duration.zero,
      ),
      throwsA(isA<UpdateInstallerException>().having(
          (error) => error.processMayBeRunning, 'may be running', true)),
    );
  });

  test('a process that fails just after creating its log is rejected',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('installer-startup-');
    addTearDown(() => directory.delete(recursive: true));
    final log = File('${directory.path}/install.log');
    await log.writeAsString('startup log');
    var reads = 0;
    await expectLater(
      waitForInstallerStartup(
        log: log,
        readExitCode: () => ++reads > 1 ? 1 : null,
        pollInterval: const Duration(milliseconds: 2),
        settleTime: const Duration(milliseconds: 10),
      ),
      throwsA(isA<UpdateInstallerException>()),
    );
  });
}
