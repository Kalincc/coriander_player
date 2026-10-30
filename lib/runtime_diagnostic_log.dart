import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/utils.dart';

/// Only anomalies and exit summaries, never normal progress ticks.
class RuntimeDiagnosticLog {
  RuntimeDiagnosticLog({required this.directory, this.maxBytes = 256 * 1024});

  static final instance = RuntimeDiagnosticLog(directory: getAppDataDir);
  final Future<Directory> Function() directory;
  final int maxBytes;
  Future<void> _tail = Future.value();
  int _queued = 0;

  Future<void> record(String message) {
    // Diagnostic I/O must not grow an unbounded queue on an unresponsive disk.
    if (_queued >= 32) return _tail;
    _queued++;
    final line = '${DateTime.now().toIso8601String()} '
        '${message.replaceAll('\n', ' ').replaceAll('\r', ' ')}\n';
    _tail = _tail.then((_) async {
      final dir = await directory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/runtime_diagnostics.log');
      if (await file.exists() && await file.length() >= maxBytes) {
        final previous = File('${dir.path}/runtime_diagnostics.previous.log');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      await file.writeAsString(line, mode: FileMode.append);
    }).catchError((Object error, StackTrace trace) {
      // Diagnostic failures must never break playback or prevent application exit.
      LOGGER.w('[runtime diagnostics] $error');
    }).whenComplete(() => _queued--);
    return _tail;
  }
}
