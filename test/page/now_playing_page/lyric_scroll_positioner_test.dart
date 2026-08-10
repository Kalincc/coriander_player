import 'dart:async';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/horizontal_lyric_view.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_scroll_positioner.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:coriander_player/play_service/lyric_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'centers the current tile for initial positioning and lyric changes',
    (tester) async {
      final currentTileKey = GlobalKey();
      final currentLine = ValueNotifier(0);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: ValueListenableBuilder<int>(
                valueListenable: currentLine,
                builder: (context, line, _) => ListView(
                  children: [
                    const SizedBox(height: 400),
                    SizedBox(
                      key: line == 0 ? currentTileKey : null,
                      height: 40,
                    ),
                    const SizedBox(height: 120),
                    SizedBox(
                      key: line == 1 ? currentTileKey : null,
                      height: 120,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await LyricScrollPositioner.center(currentTileKey, animate: false);
      await tester.pump();
      expect(_distanceFromViewportCenter(tester, currentTileKey), lessThan(1));

      currentLine.value = 1;
      await tester.pump();
      await LyricScrollPositioner.center(currentTileKey, animate: false);
      await tester.pump();
      expect(_distanceFromViewportCenter(tester, currentTileKey), lessThan(1));
    },
  );

  test('preference changes make lyric service re-emit the current line',
      () async {
    final originalPreference = AppPreference.instance.nowPlayingPagePref;
    final preference = NowPlayingPagePreference(
      NowPlayingViewMode.withLyric,
      LyricTextAlign.left,
      22,
      18,
    );
    AppPreference.instance.nowPlayingPagePref = preference;

    final delegate = _FakeLyricServiceDelegate(position: 6);
    final service = LyricService.withDelegate(delegate);
    final emittedLines = <int>[];
    final subscription = service.lyricLineStream.listen(emittedLines.add);
    var serviceDisposed = false;

    try {
      service.useSpecificLyric(
        Lrc(
          [
            LrcLine(Duration.zero, 'zero', isBlank: false),
            LrcLine(const Duration(seconds: 5), 'five', isBlank: false),
          ],
          LrcSource.local,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      emittedLines.clear();

      preference.setLyricOffsetMs(2000);
      await Future<void>.delayed(Duration.zero);

      expect(emittedLines, [0]);

      final positionReadCount = delegate.positionReadCount;
      service.dispose();
      serviceDisposed = true;
      preference.setShowTranslation(false);
      await Future<void>.delayed(Duration.zero);
      expect(delegate.positionReadCount, positionReadCount);
    } finally {
      if (!serviceDisposed) service.dispose();
      await subscription.cancel();
      await delegate.close();
      AppPreference.instance.nowPlayingPagePref = originalPreference;
    }
  });

  test('position rollback re-emits the earlier offset-aware lyric line',
      () async {
    final originalPreference = AppPreference.instance.nowPlayingPagePref;
    final preference = NowPlayingPagePreference(
      NowPlayingViewMode.withLyric,
      LyricTextAlign.left,
      22,
      18,
      lyricOffsetMs: 1000,
    );
    AppPreference.instance.nowPlayingPagePref = preference;

    final delegate = _FakeLyricServiceDelegate(position: 0);
    final service = LyricService.withDelegate(delegate);
    final emittedLines = <int>[];
    final subscription = service.lyricLineStream.listen(emittedLines.add);

    try {
      service.useSpecificLyric(
        Lrc(
          [
            LrcLine(Duration.zero, 'zero', isBlank: false),
            LrcLine(const Duration(seconds: 5), 'five', isBlank: false),
            LrcLine(const Duration(seconds: 10), 'ten', isBlank: false),
          ],
          LrcSource.local,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      emittedLines.clear();

      delegate.emitPosition(11);
      await Future<void>.delayed(Duration.zero);
      delegate.emitPosition(6);
      await Future<void>.delayed(Duration.zero);

      expect(emittedLines, [2, 1]);
    } finally {
      service.dispose();
      await subscription.cancel();
      await delegate.close();
      AppPreference.instance.nowPlayingPagePref = originalPreference;
    }
  });

  testWidgets('vertical lyric tiles obey the translation preference',
      (tester) async {
    final originalPreference = AppPreference.instance.nowPlayingPagePref;
    final preference = NowPlayingPagePreference(
      NowPlayingViewMode.withLyric,
      LyricTextAlign.left,
      22,
      18,
      showTranslation: false,
    );
    AppPreference.instance.nowPlayingPagePref = preference;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ChangeNotifierProvider(
              create: (_) => LyricViewController(),
              child: LyricViewTile(
                line: LrcLine(
                  Duration.zero,
                  'primary┃translation',
                  isBlank: false,
                ),
                opacity: 0.18,
              ),
            ),
          ),
        ),
      );

      expect(find.text('primary'), findsOneWidget);
      expect(find.text('translation'), findsNothing);
    } finally {
      AppPreference.instance.nowPlayingPagePref = originalPreference;
    }
  });

  test('horizontal lyrics use presentation without changing scroll duration',
      () {
    final line = LrcLine(
      const Duration(seconds: 5),
      'primary┃translation',
      isBlank: false,
      length: const Duration(seconds: 3),
    );

    expect(horizontalLyricText(line, showTranslation: false), 'primary');
    expect(
      horizontalLyricText(line, showTranslation: true),
      'primary┃translation',
    );
    expect(
      horizontalLyricScrollDuration(
        line,
        waitFor: const Duration(milliseconds: 300),
      ),
      const Duration(milliseconds: 2400),
    );
  });
}

class _FakeLyricServiceDelegate implements LyricServiceDelegate {
  _FakeLyricServiceDelegate({required double position}) : _position = position;

  final double _position;

  int positionReadCount = 0;
  final _positionController = StreamController<double>.broadcast();

  @override
  Future<bool> get canSendDesktopLyric async => false;

  @override
  Audio? get nowPlaying => null;

  @override
  Stream<double> get positionStream => _positionController.stream;

  @override
  double get position {
    positionReadCount += 1;
    return _position;
  }

  @override
  void sendDesktopLyricLine(LyricLine line) {}

  void emitPosition(double position) => _positionController.add(position);

  Future<void> close() => _positionController.close();
}

double _distanceFromViewportCenter(WidgetTester tester, GlobalKey targetKey) {
  final viewport = tester.getRect(find.byType(Scrollable).first);
  final target = tester.getRect(find.byKey(targetKey));
  return (target.center.dy - viewport.center.dy).abs();
}
