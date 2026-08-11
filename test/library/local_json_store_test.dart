import 'dart:io';

import 'package:coriander_player/library/local_json_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coriander-json-store-');
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('returns decoded JSON and null for a missing file', () async {
    final store = LocalJsonStore(directory);
    await File('${directory.path}${Platform.pathSeparator}saved.json')
        .writeAsString('{"version": 1, "items": ["song"]}');

    expect(await store.read('saved.json'), {
      'version': 1,
      'items': ['song'],
    });
    expect(await store.read('missing.json'), isNull);
  });

  test('replaces a JSON file and retains the prior version as a backup',
      () async {
    final store = LocalJsonStore(directory);
    final target = File('${directory.path}${Platform.pathSeparator}state.json');
    await target.writeAsString('{"version": 1}');

    await store.writeAtomically('state.json', {'version': 2});

    expect(await store.read('state.json'), {'version': 2});
    expect(
      await File('${target.path}.bak').readAsString(),
      '{"version": 1}',
    );
    expect(File('${target.path}.tmp').existsSync(), isFalse);
  });

  test('restores the prior file when replacing the temporary file fails',
      () async {
    final target = File('${directory.path}${Platform.pathSeparator}state.json');
    await target.writeAsString('{"version": 1}');
    final store = LocalJsonStore(
      directory,
      moveFile: (source, destination) async {
        if (source.path.endsWith('.tmp')) {
          throw const FileSystemException('simulated replace failure');
        }
        await source.rename(destination.path);
      },
    );

    await expectLater(
      store.writeAtomically('state.json', {'version': 2}),
      throwsA(isA<FileSystemException>()),
    );

    expect(await target.readAsString(), '{"version": 1}');
    expect(await File('${target.path}.bak').readAsString(), '{"version": 1}');
  });
}
