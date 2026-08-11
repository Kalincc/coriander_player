import 'dart:convert';
import 'dart:io';

typedef MoveFile = Future<void> Function(File source, File destination);

class LocalJsonStore {
  LocalJsonStore(this.directory, {MoveFile? moveFile})
      : _moveFile = moveFile ?? _renameFile;

  final Directory directory;
  final MoveFile _moveFile;

  Future<Object?> read(String fileName) async {
    final primary = File(_pathFor(fileName));
    final backup = File('${primary.path}.bak');

    if (!await primary.exists()) {
      if (await backup.exists()) {
        return _readBackupAndRestorePrimary(primary, backup);
      }
      return null;
    }

    try {
      return await _decode(primary);
    } on FormatException {
      if (await backup.exists()) {
        return _readBackupAndRestorePrimary(primary, backup);
      }
      rethrow;
    }
  }

  Future<void> writeAtomically(String fileName, Object value) async {
    await directory.create(recursive: true);
    final target = File(_pathFor(fileName));
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');

    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsString(json.encode(value), flush: true);

    try {
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await target.exists()) {
        await _moveFile(target, backup);
      }
      await _moveFile(temporary, target);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.copy(target.path);
      }
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  String _pathFor(String fileName) =>
      '${directory.path}${Platform.pathSeparator}$fileName';

  Future<Object?> _decode(File file) async =>
      json.decode(await file.readAsString());

  Future<Object?> _readBackupAndRestorePrimary(
    File primary,
    File backup,
  ) async {
    final value = await _decode(backup);
    final recovery = File('${primary.path}.recovery.tmp');
    if (await recovery.exists()) {
      await recovery.delete();
    }

    try {
      await backup.copy(recovery.path);
      if (await primary.exists()) {
        await primary.delete();
      }
      await _moveFile(recovery, primary);
    } catch (_) {
      if (await recovery.exists()) {
        await recovery.delete();
      }
      rethrow;
    }
    return value;
  }

  static Future<void> _renameFile(File source, File destination) async {
    await source.rename(destination.path);
  }
}
