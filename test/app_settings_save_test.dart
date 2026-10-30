import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _Api()));

  test('settings writes serialize and recover after a failed preceding save',
      () async {
    final dir = await Directory.systemTemp.createTemp('coriander-settings-');
    const window = MethodChannel('window_manager');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final firstQuery = Completer<bool>();
    var queries = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window,
        (call) async {
      if (call.method == 'isMaximized') {
        if (++queries == 1) return firstQuery.future;
        return true;
      }
      if (call.method == 'isFullScreen') return false;
      throw StateError('Unexpected method ${call.method}');
    });
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => dir.path);
    addTearDown(() async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
      await dir.delete(recursive: true);
    });
    final first = AppSettings.instance.saveSettings(rethrowOnError: true);
    final firstFailed = expectLater(first, throwsA(isA<PlatformException>()));
    final second = AppSettings.instance.saveSettings(rethrowOnError: true);
    await Future<void>.delayed(Duration.zero);
    expect(queries, 1);
    firstQuery.completeError(StateError('window query failure'));
    await firstFailed;
    await second;
    expect(queries, 2);
    final saved = jsonDecode(
        await File('${dir.path}/coriander_player/settings.json')
            .readAsString()) as Map;
    expect(saved['IsWindowMaximized'], true);
    expect(saved['Version'], AppSettings.version);
  });
}

class _Api implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
