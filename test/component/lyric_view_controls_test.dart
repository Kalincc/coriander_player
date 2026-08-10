import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

NowPlayingPagePreference _preference({
  int lyricOffsetMs = 0,
  bool showTranslation = true,
}) =>
    NowPlayingPagePreference(
      NowPlayingViewMode.withLyric,
      LyricTextAlign.left,
      22.0,
      18.0,
      lyricOffsetMs: lyricOffsetMs,
      showTranslation: showTranslation,
    );

void main() {
  test('changes the lyric offset by 100ms and persists each change', () {
    final preference = _preference();
    var saveCount = 0;
    final controller = LyricViewController(
      preference: preference,
      savePreference: () async => saveCount++,
    );
    var notificationCount = 0;
    controller.addListener(() => notificationCount++);

    controller.increaseLyricOffset();
    expect(controller.lyricOffsetMs, lyricOffsetStepMs);
    expect(preference.lyricOffsetMs, lyricOffsetStepMs);

    controller.decreaseLyricOffset();
    expect(controller.lyricOffsetMs, 0);
    expect(preference.lyricOffsetMs, 0);
    expect(notificationCount, 2);
    expect(saveCount, 2);
  });

  test('does not move or notify past either lyric offset boundary', () {
    final upperPreference = _preference(lyricOffsetMs: lyricOffsetLimitMs);
    final lowerPreference = _preference(lyricOffsetMs: -lyricOffsetLimitMs);
    var saveCount = 0;
    final upperController = LyricViewController(
      preference: upperPreference,
      savePreference: () async => saveCount++,
    );
    final lowerController = LyricViewController(
      preference: lowerPreference,
      savePreference: () async => saveCount++,
    );
    var notificationCount = 0;
    upperController.addListener(() => notificationCount++);
    lowerController.addListener(() => notificationCount++);

    upperController.increaseLyricOffset();
    lowerController.decreaseLyricOffset();

    expect(upperController.lyricOffsetMs, lyricOffsetLimitMs);
    expect(lowerController.lyricOffsetMs, -lyricOffsetLimitMs);
    expect(notificationCount, 0);
    expect(saveCount, 0);
  });

  test('resets the lyric offset to zero', () {
    final preference = _preference(lyricOffsetMs: 700);
    var saveCount = 0;
    final controller = LyricViewController(
      preference: preference,
      savePreference: () async => saveCount++,
    );
    var notificationCount = 0;
    controller.addListener(() => notificationCount++);

    controller.resetLyricOffset();

    expect(controller.lyricOffsetMs, 0);
    expect(preference.lyricOffsetMs, 0);
    expect(notificationCount, 1);
    expect(saveCount, 1);
  });

  test('toggles translation visibility and notifies listeners', () {
    final preference = _preference();
    var saveCount = 0;
    final controller = LyricViewController(
      preference: preference,
      savePreference: () async => saveCount++,
    );
    var notificationCount = 0;
    controller.addListener(() => notificationCount++);

    controller.toggleTranslation();

    expect(controller.showTranslation, isFalse);
    expect(preference.showTranslation, isFalse);
    expect(notificationCount, 1);
    expect(saveCount, 1);
  });

  testWidgets('keeps lyric controls mounted while the offset menu is open',
      (tester) async {
    final controller = LyricViewController(
      preference: _preference(),
      savePreference: () async {},
    );
    ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
    addTearDown(() {
      ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: controller,
          child: Builder(
            builder: (context) {
              final controls =
                  const LyricViewControls().build(context) as Padding;
              final column = controls.child! as Column;
              return column.children[2];
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('调整歌词偏移；当前：0 毫秒'));
    await tester.pump();

    expect(find.text('减小 100 毫秒'), findsOneWidget);
    expect(ALWAYS_SHOW_LYRIC_VIEW_CONTROLS, isTrue);

    await tester.tap(find.text('减小 100 毫秒'));
    await tester.pumpAndSettle();

    expect(ALWAYS_SHOW_LYRIC_VIEW_CONTROLS, isFalse);
  });
}
