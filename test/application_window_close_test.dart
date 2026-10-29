import 'dart:async';

import 'package:coriander_player/component/title_bar.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'application_shutdown_test.dart' show shutdownFixture;

void main() {
  const channel = MethodChannel('window_manager');

  testWidgets('native and title-bar closes share one intercepted shutdown',
      (tester) async {
    final calls = <MethodCall>[];
    final events = <String>[];
    final saved = Completer<void>();
    final shutdown = shutdownFixture(
      events,
      savePlaylists: () async {
        events.add('playlists');
        await saved.future;
      },
      closeWindow: windowManager.destroy,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'close') await emitNativeClose(tester);
      if (call.method == 'isFullScreen' || call.method == 'isMaximized') {
        return false;
      }
      return null;
    });
    addTearDown(() {
      windowManager.removeListener(shutdown);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await shutdown.listenForWindowClose();
    await shutdown.listenForWindowClose();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WindowControlls()),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('退出'));
    await tester.pump();
    await emitNativeClose(tester);
    await emitNativeClose(tester);

    expect(
        calls.where((call) => call.method == 'setPreventClose'), hasLength(1));
    expect(calls.first.arguments, {'isPreventClose': true});
    expect(events, ['playlists']);
    expect(calls.where((call) => call.method == 'destroy'), isEmpty);

    saved.complete();
    await tester.pump();
    await emitNativeClose(tester);
    await tester.pump();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
    ]);
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    expect(calls.where((call) => call.method == 'destroy'), hasLength(1));
  });

  testWidgets('native save failure keeps the window open and allows retry',
      (tester) async {
    final events = <String>[];
    var fail = true;
    final shutdown = shutdownFixture(events, savePlaylists: () async {
      events.add('playlists');
      if (fail) throw StateError('disk full');
    });
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      windowManager.removeListener(shutdown);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await shutdown.listenForWindowClose();
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: SCAFFOLD_MESSAGER,
      home: const Scaffold(body: SizedBox()),
    ));

    await emitNativeClose(tester);
    await tester.pump();
    expect(events, ['playlists']);
    expect(find.text('保存数据失败，播放器未退出。'), findsOneWidget);

    fail = false;
    await emitNativeClose(tester);
    await tester.pump();
    expect(events, [
      'playlists',
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });

  testWidgets('native close saves again after an abandoned update save',
      (tester) async {
    final events = <String>[];
    final shutdown = shutdownFixture(events);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      windowManager.removeListener(shutdown);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await shutdown.saveUserState();
    events.clear();
    await shutdown.listenForWindowClose();
    await emitNativeClose(tester);
    await tester.pump();

    expect(events, [
      'playlists',
      'lyrics',
      'settings',
      'preferences',
      'playback',
      'hotkeys',
      'window',
    ]);
  });
}

Future<void> emitNativeClose(WidgetTester tester) async {
  final completed = Completer<void>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onEvent', {'eventName': 'close'}),
    ),
    (_) => completed.complete(),
  );
  await completed.future;
}
