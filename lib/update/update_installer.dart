import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

typedef DetachedProcessStarter = Future<int> Function(
  String executable,
  List<String> arguments,
);

class UpdateInstallerException implements Exception {
  UpdateInstallerException(
    this.message, {
    required this.log,
    this.exitCode,
    this.processMayBeRunning = false,
  });

  final String message;
  final File log;
  final int? exitCode;
  final bool processMayBeRunning;

  @override
  String toString() => '$message${exitCode == null ? "" : "（退出码 $exitCode）"}';
}

Future<int> startDetachedProcess(
  String executable,
  List<String> arguments,
) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detached,
  );
  return process.pid;
}

/// Confirms startup, not installation success. Do not parse Inno's localized,
/// version-dependent log text; require a nonempty log and a short alive period.
Future<void> waitForInstallerStartup({
  required File log,
  required int? Function() readExitCode,
  Duration timeout = const Duration(seconds: 15),
  Duration settleTime = const Duration(milliseconds: 500),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final watch = Stopwatch()..start();
  Duration? logObservedAt;
  void checkExit() {
    final code = readExitCode();
    if (code != null) {
      throw UpdateInstallerException('安装器启动后已退出', log: log, exitCode: code);
    }
  }

  while (watch.elapsed < timeout) {
    checkExit();
    if (await log.exists() && await log.length() > 0) {
      logObservedAt ??= watch.elapsed;
      if (watch.elapsed - logObservedAt >= settleTime) {
        checkExit();
        return;
      }
    }
    await Future<void>.delayed(pollInterval);
  }
  throw UpdateInstallerException('等待安装器启动日志超时',
      log: log, processMayBeRunning: true);
}

Future<void> _confirmWindowsInstallerStartup(int pid, File log) async {
  // Detached Dart processes intentionally expose no exitCode Future. Hold a
  // Windows handle while observing startup, rather than polling a reusable PID.
  final handle = win32.OpenProcess(
      win32.PROCESS_QUERY_LIMITED_INFORMATION | win32.SYNCHRONIZE, 0, pid);
  if (handle == 0) {
    throw UpdateInstallerException(
      '安装器已退出或无法监测启动状态（Windows 错误 ${win32.GetLastError()}）',
      log: log,
      processMayBeRunning: true,
    );
  }
  final code = calloc<Uint32>();
  try {
    await waitForInstallerStartup(
        log: log,
        readExitCode: () {
          final status = win32.WaitForSingleObject(handle, 0);
          if (status == win32.WAIT_TIMEOUT) return null;
          if (status == win32.WAIT_OBJECT_0 &&
              win32.GetExitCodeProcess(handle, code) != 0) {
            return code.value;
          }
          throw UpdateInstallerException('无法读取安装器状态',
              log: log, processMayBeRunning: true);
        });
  } finally {
    calloc.free(code);
    win32.CloseHandle(handle);
  }
}

class UpdateInstaller {
  UpdateInstaller({
    DetachedProcessStarter? startDetached,
    Future<void> Function(int pid, File log)? confirmStartup,
  })  : _startDetached = startDetached ?? startDetachedProcess,
        _confirmStartup = confirmStartup ?? _confirmWindowsInstallerStartup;

  final DetachedProcessStarter _startDetached;
  final Future<void> Function(int pid, File log) _confirmStartup;

  Future<void> start({required File installer, required File log}) async {
    var launched = false;
    try {
      if (await log.exists()) {
        throw UpdateInstallerException('安装日志已存在，请重新检查更新后重试', log: log);
      }
      final pid = await _startDetached(installer.path, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/CORIANDERAPPUPDATE=1',
        // Process.start quotes Windows argument-list items itself. Embedded
        // quotes are escaped and Inno would treat the escapes as path characters.
        '/LOG=${log.path}',
      ]);
      launched = true;
      await _confirmStartup(pid, log);
    } on UpdateInstallerException {
      rethrow;
    } catch (error) {
      throw UpdateInstallerException('无法确认安装器启动：$error',
          log: log, processMayBeRunning: launched);
    }
  }
}
