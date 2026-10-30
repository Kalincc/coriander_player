import 'dart:io';

import 'package:coriander_player/runtime_diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'diagnostic writes are serialized and rotate without touching user files',
      () async {
    final dir = await Directory.systemTemp.createTemp('coriander-diagnostics-');
    addTearDown(() => dir.delete(recursive: true));
    final userFile = File('${dir.path}/playlists.json');
    await userFile.writeAsString('preserve');
    final log = RuntimeDiagnosticLog(directory: () async => dir, maxBytes: 120);
    await Future.wait([
      for (var i = 0; i < 6; i++) log.record('entry-$i: playback diagnostic'),
    ]);
    final current =
        await File('${dir.path}/runtime_diagnostics.log').readAsString();
    final previous = await File('${dir.path}/runtime_diagnostics.previous.log')
        .readAsString();
    expect(current, contains('entry-5'));
    expect(previous, isNotEmpty);
    expect(await userFile.readAsString(), 'preserve');
    expect(current.length, lessThan(240));
    expect(previous.length, lessThan(240));
  });

  test('a diagnostic failure is nonfatal and a later write can succeed',
      () async {
    final dir = await Directory.systemTemp.createTemp('coriander-diagnostics-');
    addTearDown(() => dir.delete(recursive: true));
    var fail = true;
    final log = RuntimeDiagnosticLog(directory: () async {
      if (fail) throw const FileSystemException('unavailable');
      return dir;
    });
    await log.record('failed');
    fail = false;
    await log.record('recovered');
    expect(await File('${dir.path}/runtime_diagnostics.log').readAsString(),
        contains('recovered'));
  });
}
