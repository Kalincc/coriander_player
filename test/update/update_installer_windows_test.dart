import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in ['install.log', '中文目录 with spaces/install.log']) {
    test('real Windows process preserves the Inno log argument: $name',
        () async {
      final probe = await _probe(name: name);
      await probe.installer.start(installer: File('probe.exe'), log: probe.log);
      final args = jsonDecode(
              await File('${probe.log.path}.arguments.json').readAsString())
          as List;
      expect(args.where((value) => (value as String).startsWith('/LOG=')),
          ['/LOG=${probe.log.path}']);
      expect(await probe.log.length(), greaterThan(0));
    }, skip: !Platform.isWindows);
  }

  test('the previous embedded quotes fail across a real Windows process',
      () async {
    final probe =
        await _probe(name: '中文目录 with spaces/install.log', legacy: true);
    await expectLater(
      probe.installer.start(installer: File('probe.exe'), log: probe.log),
      throwsA(isA<UpdateInstallerException>()),
    );
    expect(await probe.log.exists(), isFalse);
  }, skip: !Platform.isWindows);

  test('a real installer child that exits early never completes the handoff',
      () async {
    final probe = await _probe(name: 'install.log', exitEarly: true);
    await expectLater(
      probe.installer.start(installer: File('probe.exe'), log: probe.log),
      throwsA(isA<UpdateInstallerException>()),
    );
    expect(await probe.log.exists(), isFalse);
  }, skip: !Platform.isWindows);
}

Future<({UpdateInstaller installer, File log})> _probe({
  required String name,
  bool legacy = false,
  bool exitEarly = false,
}) async {
  final directory = await Directory.systemTemp.createTemp('installer-win-');
  final log = File('${directory.path}/$name').absolute;
  await log.parent.create(recursive: true);
  Process? child;
  addTearDown(() async {
    await File('${log.path}.stop').writeAsString('stop');
    if (child != null) {
      try {
        await child!.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        child!.kill();
        await child!.exitCode;
      }
    }
    await directory.delete(recursive: true);
  });
  final config =
      jsonDecode(await File('.dart_tool/package_config.json').readAsString())
          as Map;
  final flutterRoot =
      Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
  final dart = File('${flutterRoot.path}/bin/cache/dart-sdk/bin/dart.exe');
  final fixture = File('test/fixtures/update_installer_probe.dart').absolute;
  final installer = UpdateInstaller(startDetached: (_, args) async {
    final forwarded = legacy
        ? [
            for (final arg in args)
              arg.startsWith('/LOG=') ? '/LOG="${arg.substring(5)}"' : arg
          ]
        : args;
    child = await Process.start(
        dart.path, [fixture.path, if (exitEarly) '--exit-early', ...forwarded]);
    // Drain redirected pipes; the fixture never launches a real installer.
    child!.stdout.drain<void>();
    child!.stderr.drain<void>();
    return child!.pid;
  });
  return (installer: installer, log: log);
}
