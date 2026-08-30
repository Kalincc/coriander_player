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
      },
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
          r'/LOG="C:\Temp\Coriander.Install.log"',
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
      throwsA(isA<StateError>()),
    );
  });
}
