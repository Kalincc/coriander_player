import 'dart:io';

import 'package:coriander_player/update/update_installer.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length != 3) {
    exitCode = 2;
    return;
  }
  final oldPid = int.tryParse(args[0]);
  if (oldPid == null || oldPid <= 0 || oldPid == pid) {
    exitCode = 2;
    return;
  }
  final installer = File(args[1]);
  final log = File(args[2]);
  final result = File('${log.path}.handoff.txt');
  final cancel = handoffCancelFile(log);
  var handle = 0;
  var acknowledged = false;
  try {
    handle = win32.OpenProcess(win32.SYNCHRONIZE, 0, oldPid);
    if (handle == 0) {
      throw StateError('无法打开播放器进程（Windows 错误 ${win32.GetLastError()}）');
    }
    if (await cancel.exists()) return;
    if (!await installer.exists()) throw StateError('安装包不存在');
    await handoffReadyFile(log).writeAsString('ready', flush: true);
    acknowledged = true;
    final status = win32.WaitForSingleObject(handle, 45000);
    if (await cancel.exists()) return;
    if (status != win32.WAIT_OBJECT_0) {
      throw StateError(status == win32.WAIT_TIMEOUT
          ? '等待旧播放器退出超时，未启动安装器'
          : '无法确认旧播放器已退出，未启动安装器');
    }
    final installed = await Process.start(
      installer.path,
      updateInstallerArguments(log),
      workingDirectory: installer.parent.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await installed.exitCode;
    if (code != 0) {
      throw StateError('安装未完成（安装器退出码 $code）');
    }
    await result.writeAsString('installer exit code: 0', flush: true);
  } catch (error) {
    exitCode = 1;
    try {
      await result.writeAsString('$error', flush: true);
    } on FileSystemException {
      // Report the original failure even if the diagnostic file is unwritable.
    }
    if (acknowledged && !await cancel.exists()) {
      using((arena) => win32.MessageBox(
            0,
            '$error\n\n安装包已保留：${installer.path}\n安装日志：${log.path}'
                .toNativeUtf16(allocator: arena),
            'Coriander Player 更新失败'.toNativeUtf16(allocator: arena),
            win32.MB_OK | win32.MB_ICONERROR | win32.MB_SETFOREGROUND,
          ));
    }
  } finally {
    if (handle != 0) win32.CloseHandle(handle);
  }
}
