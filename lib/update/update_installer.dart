import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart' as win32;

const updateHandoffExecutable = 'coriander_update_handoff.exe';

File handoffReadyFile(File log) => File('${log.path}.ready');
File handoffCancelFile(File log) => File('${log.path}.cancel');

List<String> updateInstallerArguments(File log) => [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/CORIANDERAPPUPDATE=1',
      // Dart quotes argument-list items itself, including paths with spaces.
      '/LOG=${log.path}',
    ];

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

/// Acknowledgement means the helper holds the old process handle.
Future<void> waitForHandoffReady({
  required File log,
  required int? Function() readExitCode,
  Duration timeout = const Duration(seconds: 15),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final watch = Stopwatch()..start();
  final ready = handoffReadyFile(log);
  void checkExit() {
    final code = readExitCode();
    if (code != null) {
      throw UpdateInstallerException('更新助手提前退出', log: log, exitCode: code);
    }
  }

  while (watch.elapsed < timeout) {
    checkExit();
    if (await ready.exists() && await ready.length() > 0) {
      checkExit();
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
  throw UpdateInstallerException('等待更新助手确认超时',
      log: log, processMayBeRunning: true);
}

Future<void> _confirmWindowsHandoff(int pid, File log) async {
  // Detached Dart processes intentionally expose no exitCode Future. Hold a
  // Windows handle while observing startup, rather than polling a reusable PID.
  final handle = win32.OpenProcess(
      win32.PROCESS_QUERY_LIMITED_INFORMATION | win32.SYNCHRONIZE, 0, pid);
  if (handle == 0) {
    throw UpdateInstallerException(
      '更新助手已退出或无法监测启动状态（Windows 错误 ${win32.GetLastError()}）',
      log: log,
      processMayBeRunning: true,
    );
  }
  final code = calloc<Uint32>();
  try {
    await waitForHandoffReady(
        log: log,
        readExitCode: () {
          final status = win32.WaitForSingleObject(handle, 0);
          if (status == win32.WAIT_TIMEOUT) return null;
          if (status == win32.WAIT_OBJECT_0 &&
              win32.GetExitCodeProcess(handle, code) != 0) {
            return code.value;
          }
          throw UpdateInstallerException('无法读取更新助手状态',
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
    File? helper,
  })  : _startDetached = startDetached ?? startDetachedProcess,
        _confirmStartup = confirmStartup ?? _confirmWindowsHandoff,
        _helper = helper;

  final DetachedProcessStarter _startDetached;
  final Future<void> Function(int pid, File log) _confirmStartup;
  final File? _helper;

  Future<void> cancelHandoff(File log) =>
      handoffCancelFile(log).writeAsString('cancel', flush: true);

  Future<void> start({required File installer, required File log}) async {
    var launched = false;
    try {
      if (await log.exists() ||
          await handoffReadyFile(log).exists() ||
          await handoffCancelFile(log).exists()) {
        throw UpdateInstallerException('更新目录已被使用，请重新检查更新后重试', log: log);
      }
      final source = _helper ??
          File(path.join(path.dirname(Platform.resolvedExecutable),
              updateHandoffExecutable));
      // The installed helper must not hold its own destination file open.
      final staged = await source
          .copy(path.join(installer.parent.path, updateHandoffExecutable));
      final helperPid = await _startDetached(staged.path, [
        '$pid',
        installer.absolute.path,
        log.absolute.path,
      ]);
      launched = true;
      await _confirmStartup(helperPid, log);
    } catch (error) {
      if (launched) {
        try {
          await cancelHandoff(log);
        } catch (cancelError) {
          throw UpdateInstallerException('无法取消更新交接：$cancelError',
              log: log, processMayBeRunning: true);
        }
      }
      if (error is UpdateInstallerException) rethrow;
      throw UpdateInstallerException('无法启动更新助手：$error', log: log);
    }
  }
}
