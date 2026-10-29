import 'dart:convert';
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

  test('reads the backup when the primary JSON is missing', () async {
    final store = LocalJsonStore(directory);
    final primary =
        File('${directory.path}${Platform.pathSeparator}saved.json');
    await File('${primary.path}.bak')
        .writeAsString('{"version": 1, "items": ["backup"]}');

    expect(await store.read('saved.json'), {
      'version': 1,
      'items': ['backup'],
    });
    expect(jsonDecode(await primary.readAsString()), {
      'version': 1,
      'items': ['backup'],
    });
  });

  test('reads the backup when the primary JSON is corrupt', () async {
    final store = LocalJsonStore(directory);
    final primary =
        File('${directory.path}${Platform.pathSeparator}saved.json');
    await primary.writeAsString('{not valid JSON');
    await File('${primary.path}.bak')
        .writeAsString('{"version": 1, "items": ["backup"]}');

    expect(await store.read('saved.json'), {
      'version': 1,
      'items': ['backup'],
    });
    expect(jsonDecode(await primary.readAsString()), {
      'version': 1,
      'items': ['backup'],
    });
  });

  List<String> parseItems(Object? value) {
    if (value is! Map || value['items'] is! List) {
      throw const FormatException('Invalid saved items');
    }
    final items = value['items'] as List;
    if (items.any((item) => item is! String)) {
      throw const FormatException('Invalid saved item');
    }
    return items.cast<String>();
  }

  test('validates both copies before restoring a schema-valid backup',
      () async {
    final store = LocalJsonStore(directory);
    final primary = File('${directory.path}/saved.json');
    final backup = File('${primary.path}.bak');
    const validBackup = '{"items":["backup"]}';
    await primary.writeAsString('{"items":[false]}');
    await backup.writeAsString(validBackup);

    expect(await store.readValidated('saved.json', parseItems), ['backup']);
    expect(await primary.readAsString(), validBackup);
    expect(await backup.readAsString(), validBackup);
  });

  test('keeps both originals when neither copy passes schema validation',
      () async {
    final store = LocalJsonStore(directory);
    final primary = File('${directory.path}/saved.json');
    final backup = File('${primary.path}.bak');
    const badPrimary = '{"items":[false]}';
    const badBackup = '{"items":"broken"}';
    await primary.writeAsString(badPrimary);
    await backup.writeAsString(badBackup);

    await expectLater(
      store.readValidated('saved.json', parseItems),
      throwsFormatException,
    );

    expect(await primary.readAsString(), badPrimary);
    expect(await backup.readAsString(), badBackup);
    expect(File('${primary.path}.recovery.tmp').existsSync(), isFalse);
  });

  test('does not replace a valid primary with an invalid backup', () async {
    final store = LocalJsonStore(directory);
    final primary = File('${directory.path}/saved.json');
    final backup = File('${primary.path}.bak');
    await primary.writeAsString('{"items":["primary"]}');
    await backup.writeAsString('{"items":"broken"}');

    expect(await store.readValidated('saved.json', parseItems), ['primary']);
    expect(await backup.readAsString(), '{"items":"broken"}');
  });

  test('keeps the only backup if a missing-primary replacement fails',
      () async {
    final primary = File('${directory.path}/saved.json');
    final backup = File('${primary.path}.bak');
    const validBackup = '{"items":["backup"]}';
    await backup.writeAsString(validBackup);
    final store =
        LocalJsonStore(directory, moveFile: (source, destination) async {
      throw const FileSystemException('simulated replace failure');
    });

    await expectLater(
      store.writeAtomically('saved.json', {
        'items': ['new']
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(await primary.readAsString(), validBackup);
    expect(await backup.readAsString(), validBackup);
    expect(File('${primary.path}.tmp').existsSync(), isFalse);
  });

  test('keeps recovered data in the backup after a later write failure',
      () async {
    final primary =
        File('${directory.path}${Platform.pathSeparator}saved.json');
    final backup = File('${primary.path}.bak');
    await backup.writeAsString('{"version": 1, "items": ["backup"]}');
    await LocalJsonStore(directory).read('saved.json');
    final failingStore = LocalJsonStore(
      directory,
      moveFile: (source, destination) async {
        if (source.path.endsWith('.tmp')) {
          throw const FileSystemException('simulated replace failure');
        }
        await source.rename(destination.path);
      },
    );

    await expectLater(
      failingStore.writeAtomically('saved.json', {'version': 2}),
      throwsA(isA<FileSystemException>()),
    );

    expect(jsonDecode(await primary.readAsString()), {
      'version': 1,
      'items': ['backup'],
    });
    expect(jsonDecode(await backup.readAsString()), {
      'version': 1,
      'items': ['backup'],
    });
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
