import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/application_shutdown.dart';
import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'install_environment.dart';
import 'update_downloader.dart';
import 'update_installer.dart';
import 'update_release.dart';
import 'update_service.dart';

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateCurrent extends UpdateState {
  const UpdateCurrent();
}

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.candidate, {required this.canAutoInstall});

  final UpdateCandidate candidate;
  final bool canAutoInstall;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.candidate, this.progress);

  final UpdateCandidate candidate;
  final UpdateDownloadProgress progress;
}

class UpdateVerifying extends UpdateState {
  const UpdateVerifying(this.candidate);

  final UpdateCandidate candidate;
}

class UpdatePreparingInstall extends UpdateState {
  const UpdatePreparingInstall(this.candidate);

  final UpdateCandidate candidate;
}

class UpdateCancelled extends UpdateState {
  const UpdateCancelled();
}

class UpdateFailed extends UpdateState {
  const UpdateFailed(
    this.message, {
    required this.canRetry,
    this.releasePageUri,
  });

  final String message;
  final bool canRetry;
  final Uri? releasePageUri;
}

abstract interface class UpdateControllerView implements Listenable {
  UpdateState get state;

  Future<void> check();

  Future<void> install();

  void cancelDownload();
}

Future<Directory> _createProductionUpdateDirectory() async {
  final directory = Directory(
    path.join(Directory.systemTemp.path, 'coriander-player-update'),
  );
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
  return directory.create(recursive: true);
}

Future<void> _deleteTemporaryDirectory(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

class UpdateController extends ChangeNotifier implements UpdateControllerView {
  UpdateController({
    required UpdateService service,
    required InstallEnvironment environment,
    required UpdateDownloader downloader,
    required UpdateInstaller installer,
    required ApplicationShutdown shutdown,
    required Future<Directory> Function() createTemporaryDirectory,
    Future<void> Function(Directory directory)? cleanupTemporaryDirectory,
    ForkReleaseVersion? currentVersion,
  })  : _service = service,
        _environment = environment,
        _downloader = downloader,
        _installer = installer,
        _shutdown = shutdown,
        _createTemporaryDirectory = createTemporaryDirectory,
        _cleanupTemporaryDirectory =
            cleanupTemporaryDirectory ?? _deleteTemporaryDirectory,
        _currentVersion =
            currentVersion ?? ForkReleaseVersion.parse(AppSettings.version);

  factory UpdateController.production() {
    return UpdateController(
      service: UpdateService.github(AppSettings.github),
      environment: InstallEnvironment.windows(),
      downloader: UpdateDownloader(),
      installer: UpdateInstaller(),
      shutdown: ApplicationShutdown.production(),
      createTemporaryDirectory: _createProductionUpdateDirectory,
    );
  }

  final UpdateService _service;
  final InstallEnvironment _environment;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;
  final ApplicationShutdown _shutdown;
  final Future<Directory> Function() _createTemporaryDirectory;
  final Future<void> Function(Directory directory) _cleanupTemporaryDirectory;
  final ForkReleaseVersion _currentVersion;

  UpdateState _state = const UpdateIdle();
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  UpdateCancellation? _cancellation;

  @override
  UpdateState get state => _state;

  @override
  Future<void> check() async {
    if (_disposed || _busy) return;

    final generation = ++_generation;
    _busy = true;
    _setState(const UpdateChecking());
    try {
      final candidate = await _service.check(_currentVersion);
      if (!_isCurrent(generation)) return;
      if (candidate == null) {
        _setState(const UpdateCurrent());
      } else {
        _setState(UpdateAvailable(
          candidate,
          canAutoInstall: _environment.isInstalledEdition(),
        ));
      }
    } on UpdateAssetException catch (error) {
      if (_isCurrent(generation)) {
        _setState(UpdateFailed(
          '该版本缺少可验证的安装包，请打开发布页面手动下载。',
          canRetry: false,
          releasePageUri: error.releasePageUri,
        ));
      }
    } catch (error, stackTrace) {
      if (_isCurrent(generation)) {
        LOGGER.e(error, stackTrace: stackTrace);
        _setState(const UpdateFailed(
          '检查更新失败，请稍后重试。',
          canRetry: true,
        ));
      }
    } finally {
      if (_isCurrent(generation)) _busy = false;
    }
  }

  @override
  Future<void> install() async {
    if (_disposed || _busy) return;
    final available = _state;
    if (available is! UpdateAvailable || !available.canAutoInstall) return;

    final generation = ++_generation;
    _busy = true;
    final cancellation = UpdateCancellation();
    _cancellation = cancellation;
    final candidate = available.candidate;
    Directory? temporaryDirectory;
    var installerStarted = false;

    try {
      temporaryDirectory = await _createTemporaryDirectory();
      if (!_isCurrent(generation)) return;

      final verified = await _downloader.downloadAndVerify(
        candidate,
        temporaryDirectory,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!_isCurrent(generation)) return;
          if (progress.phase == UpdateDownloadPhase.verifying) {
            _setState(UpdateVerifying(candidate));
          } else {
            _setState(UpdateDownloading(candidate, progress));
          }
        },
      );
      if (!_isCurrent(generation)) return;

      _setState(UpdatePreparingInstall(candidate));
      await _shutdown.saveUserState();
      if (!_isCurrent(generation)) return;

      await _installer.start(
        installer: verified.installer,
        log: verified.installLog,
      );
      installerStarted = true;
      await _shutdown.closeAfterUpdateHandoff();
    } on UpdateCancelledException {
      if (_isCurrent(generation)) _setState(const UpdateCancelled());
    } on UpdateHashMismatchException {
      if (_isCurrent(generation)) {
        _setState(const UpdateFailed('安装包校验失败，请重试。', canRetry: true));
      }
    } on UpdateDownloadException catch (error, stackTrace) {
      if (_isCurrent(generation)) {
        LOGGER.e(error, stackTrace: stackTrace);
        _setState(const UpdateFailed('下载更新失败，请检查网络后重试。', canRetry: true));
      }
    } catch (error, stackTrace) {
      if (_isCurrent(generation)) {
        LOGGER.e(error, stackTrace: stackTrace);
        _setState(const UpdateFailed('更新失败，请重试。', canRetry: true));
      }
    } finally {
      if (!installerStarted && temporaryDirectory != null) {
        try {
          await _cleanupTemporaryDirectory(temporaryDirectory);
        } catch (error, stackTrace) {
          LOGGER.e(
            '清理更新临时文件失败。',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      if (_isCurrent(generation)) {
        _busy = false;
        _cancellation = null;
      }
    }
  }

  @override
  void cancelDownload() {
    if (_disposed || _state is! UpdateDownloading) return;
    _cancellation?.cancel();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setState(UpdateState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    super.dispose();
  }
}
