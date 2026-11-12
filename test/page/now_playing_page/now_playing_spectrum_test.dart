import 'dart:async';
import 'dart:typed_data';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/page/now_playing_page/component/now_playing_spectrum.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only the enabled, visible shared page subscribes to playback',
      (tester) async {
    final fixture = _SpectrumFixture();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(fixture.dispose);
    await tester
        .pumpWidget(MaterialApp(navigatorKey: navigator, home: fixture.page()));

    final menu = find.byTooltip('频谱可视化');
    expect(fixture.positions.hasListener, isFalse);
    expect(find.text('原背景'), findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('镜像反射'));
    await tester.pumpAndSettle();
    expect(fixture.options.value.style, SpectrumStyle.mirror);
    expect(fixture.positions.hasListener, isTrue);
    expect(fixture.reads, 0, reason: 'Do not start another timer');
    fixture.positions.add(.5);
    await tester.pump();
    expect(fixture.reads, 1);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('粒子效果'));
    await tester.pumpAndSettle();
    expect(fixture.options.value.particles, isFalse);
    await tester.tap(find.text('歌词与控件'));
    expect(fixture.foregroundTaps, 1);

    fixture.exclusive.value = true;
    await tester.pump();
    expect(find.text('原背景'), findsOneWidget);
    expect(fixture.positions.hasListener, isFalse);
    final disabledMenu = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '频谱可视化（仅共享模式）'));
    expect(disabledMenu.onPressed, isNull);
    fixture.positions.add(1);
    await tester.pump();
    expect(fixture.reads, 1);

    fixture.exclusive.value = false;
    await tester.pump();
    expect(
        fixture.options.value, (style: SpectrumStyle.mirror, particles: false));
    expect(fixture.positions.hasListener, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(fixture.positions.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fixture.positions.hasListener, isTrue);

    unawaited(navigator.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('其他页面')),
    )));
    await tester.pumpAndSettle();
    expect(fixture.positions.hasListener, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fixture.positions.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.positions.hasListener, isFalse);
    expect(fixture.states.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paints the three styles, caps dots, and clears on pause',
      (tester) async {
    final fixture = _SpectrumFixture();
    addTearDown(fixture.dispose);
    fixture.options.value = (style: SpectrumStyle.bars, particles: true);
    await tester.pumpWidget(MaterialApp(home: fixture.page()));
    fixture.positions.add(.5);
    await tester.pump();
    final bars = _draw(tester);
    final lines = _calls(bars, #drawLine);
    expect(lines, hasLength(48));
    expect(_calls(bars, #drawCircle), hasLength(24));
    expect(lines.first[0].dx, lines.first[1].dx);
    expect(lines.first[0].dy, greaterThan(lines.first[1].dy));

    fixture.options.value = (style: SpectrumStyle.mirror, particles: false);
    await tester.pump();
    final mirror = _draw(tester);
    final mirroredLines = _calls(mirror, #drawLine);
    expect(mirroredLines, hasLength(96));
    expect(mirroredLines[0][0], mirroredLines[1][0]);
    expect(
        (mirroredLines[0][1] + mirroredLines[1][1]) / 2.0, mirroredLines[0][0]);
    expect(_calls(mirror, #drawCircle), isEmpty);

    fixture.options.value = (style: SpectrumStyle.circle, particles: true);
    await tester.pump();
    final circle = _calls(_draw(tester), #drawLine);
    expect(circle, hasLength(48));
    expect(circle[12][0].dx, lessThan(circle[12][1].dx));
    expect(circle[12][0].dy, closeTo(circle[12][1].dy, 1e-8));

    fixture.states.add(PlayerState.paused);
    await tester.pump();
    expect(_calls(_draw(tester), #drawLine), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.reads, 1);
    expect(tester.takeException(), isNull);
  });
}

TestRecordingCanvas _draw(WidgetTester tester) {
  final painting = find.descendant(
      of: find.byType(NowPlayingSpectrum), matching: find.byType(CustomPaint));
  final canvas = TestRecordingCanvas();
  tester
      .widget<CustomPaint>(painting)
      .painter!
      .paint(canvas, tester.getSize(painting));
  return canvas;
}

List<List<dynamic>> _calls(TestRecordingCanvas canvas, Symbol method) =>
    canvas.invocations
        .where((record) => record.invocation.memberName == method)
        .map((record) => record.invocation.positionalArguments)
        .toList();

class _SpectrumFixture {
  final options = ValueNotifier<SpectrumOptions>(
      (style: SpectrumStyle.off, particles: true));
  final exclusive = ValueNotifier(false);
  final positions = StreamController<double>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  int reads = 0;
  int foregroundTaps = 0;

  Widget page() => Scaffold(
        appBar: AppBar(actions: [
          SpectrumMenu(
            options: options,
            exclusive: exclusive,
            onChanged: (value) => options.value = value,
          ),
        ]),
        body: Stack(fit: StackFit.expand, children: [
          NowPlayingSpectrum(
            options: options,
            exclusive: exclusive,
            positions: positions.stream,
            playerStates: states.stream,
            readSpectrum: (Float32List bins) {
              reads++;
              bins.fillRange(0, bins.length, .15);
              return 192000;
            },
            fallback: const Text('原背景'),
          ),
          Center(
            child: TextButton(
              onPressed: () => foregroundTaps++,
              child: const Text('歌词与控件'),
            ),
          ),
        ]),
      );

  Future<void> dispose() async {
    options.dispose();
    exclusive.dispose();
    await positions.close();
    await states.close();
  }
}
