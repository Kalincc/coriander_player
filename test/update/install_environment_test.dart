import 'package:coriander_player/update/install_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts matching registered and executable directories', () {
    final environment = InstallEnvironment(
      readInstallLocation: () => 'C:\\Apps\\Coriander Player\\',
      executablePath: () => r'c:\apps\coriander player\coriander_player.exe',
      isWindows: () => true,
    );

    expect(environment.isInstalledEdition(), isTrue);
  });

  test('treats a different executable directory as portable', () {
    final environment = InstallEnvironment(
      readInstallLocation: () => r'C:\Apps\Coriander Player',
      executablePath: () => r'D:\Portable\coriander_player.exe',
      isWindows: () => true,
    );

    expect(environment.isInstalledEdition(), isFalse);
  });

  test('treats missing registration as portable', () {
    final environment = InstallEnvironment(
      readInstallLocation: () => null,
      executablePath: () => r'C:\Portable\coriander_player.exe',
      isWindows: () => true,
    );

    expect(environment.isInstalledEdition(), isFalse);
  });

  test('treats registry read errors as portable', () {
    final environment = InstallEnvironment(
      readInstallLocation: () => throw StateError('registry unavailable'),
      executablePath: () => r'C:\Portable\coriander_player.exe',
      isWindows: () => true,
    );

    expect(environment.isInstalledEdition(), isFalse);
  });

  test('treats non-Windows platforms as portable', () {
    final environment = InstallEnvironment(
      readInstallLocation: () => r'C:\Apps\Coriander Player',
      executablePath: () => r'C:\Apps\Coriander Player\coriander_player.exe',
      isWindows: () => false,
    );

    expect(environment.isInstalledEdition(), isFalse);
  });
}
