import 'dart:convert';
import 'dart:io';

typedef MoveFile = Future<void> Function(File source, File destination);

class LocalJsonStore {
  LocalJsonStore(this.directory, {MoveFile? moveFile})
      : _moveFile = moveFile ?? _renameFile;

  final Directory directory;
  final MoveFile _moveFile;

  Future<Object?> read(String fileName) =>
      readValidated<Object?>(fileName, (value) => value);

  /// Tries the backup when either JSON decoding or schema validation fails.
  Future<T?> readValidated<T>(
    String fileName,
    T Function(Object? value) parse,
  ) async {
    final primary = File(_pathFor(fileName));
    final backup = File('${primary.path}.bak');

    if (!await primary.exists()) {
      if (await backup.exists()) {
        return _readBackupAndRestorePrimary(primary, backup, parse);
      }
      return null;
    }

    try {
      return parse(await _decode(primary));
    } catch (error) {
      if ((error is FormatException || error is FileSystemException) &&
          await backup.exists()) {
        return _readBackupAndRestorePrimary(primary, backup, parse);
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
      if (await target.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
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

  Future<T> _readBackupAndRestorePrimary<T>(
    File primary,
    File backup,
    T Function(Object? value) parse,
  ) async {
    final value = parse(await _decode(backup));
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
