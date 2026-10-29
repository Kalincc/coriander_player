import 'dart:async';

import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'transition owns one subscription and releases animation on unmount',
      (tester) async {
    var listeners = 0;
    final positions = StreamController<double>.broadcast(
      onListen: () => listeners++,
      onCancel: () => listeners--,
    );
    final line = LrcLine(Duration.zero, '',
        isBlank: true, length: const Duration(seconds: 20));
    Widget build(Brightness brightness) => Theme(
          data: ThemeData(brightness: brightness),
          child: LyricTransitionTile(
              lrcLine: line,
              positionStream: positions.stream,
              lyricOffset: () => Duration.zero),
        );
    await tester.pumpWidget(build(Brightness.light));
    positions.add(1);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(build(Brightness.dark));
    expect(listeners, 1);

    positions.add(21);
    await tester.pump();
    positions
        .add(1); // Seeking back must still work after an interval completes.
    await tester.pump(const Duration(milliseconds: 50));
    expect(listeners, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(listeners, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await positions.close();
  });
}
