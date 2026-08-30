import 'dart:io';

import 'package:path/path.dart' as path;

import '../src/windows/install_registry.dart';

const installerAppId = '{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}';
const installerRegistryPath =
    r'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}_is1';

class InstallEnvironment {
  InstallEnvironment({
    required this.readInstallLocation,
    required this.executablePath,
    required this.isWindows,
  });

  factory InstallEnvironment.windows() {
    return InstallEnvironment(
      readInstallLocation: () => readInnoInstallLocation(installerRegistryPath),
      executablePath: () => Platform.resolvedExecutable,
      isWindows: () => Platform.isWindows,
    );
  }

  final String? Function() readInstallLocation;
  final String Function() executablePath;
  final bool Function() isWindows;

  bool isInstalledEdition() {
    try {
      if (!isWindows()) {
        return false;
      }

      final registeredDirectory = readInstallLocation();
      if (registeredDirectory == null || registeredDirectory.trim().isEmpty) {
        return false;
      }

      final executableDirectory = path.windows.dirname(executablePath());
      return _normalizeDirectory(registeredDirectory) ==
          _normalizeDirectory(executableDirectory);
    } catch (_) {
      return false;
    }
  }

  String _normalizeDirectory(String value) {
    var normalized = path.windows.normalize(value.trim());
    while (normalized.length > 1 &&
        (normalized.endsWith(r'\') || normalized.endsWith('/'))) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }
}
