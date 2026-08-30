import 'dart:io';

typedef DetachedProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);

Future<void> startDetachedProcess(
  String executable,
  List<String> arguments,
) async {
  await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detached,
  );
}

class UpdateInstaller {
  UpdateInstaller({DetachedProcessStarter? startDetached})
      : _startDetached = startDetached ?? startDetachedProcess;

  final DetachedProcessStarter _startDetached;

  Future<void> start({required File installer, required File log}) async {
    await _startDetached(installer.path, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/CORIANDERAPPUPDATE=1',
      '/LOG="${log.path}"',
    ]);
  }
}
