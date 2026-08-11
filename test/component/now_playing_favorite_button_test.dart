import 'package:coriander_player/component/now_playing_favorite_button.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Audio _audio() => Audio(
      'D:/music/favorite.flac',
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      'Favorite',
      1,
      1,
      'Lofty',
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });
  testWidgets('disables the favorite control when there is no current audio',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NowPlayingFavoriteButton(audio: null)),
    );

    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  testWidgets('toggles liked state without asking the playback service to play',
      (tester) async {
    final audio = _audio();
    var liked = false;
    var toggleCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NowPlayingFavoriteButton(
          audio: audio,
          isLiked: (_) => liked,
          onToggle: (_) async {
            toggleCount++;
            liked = !liked;
            playlistRevision.value++;
          },
        ),
      ),
    );

    Icon favoriteIcon() => tester.widget<Icon>(
          find.byWidgetPredicate(
            (widget) => widget is Icon && widget.icon == Symbols.favorite,
          ),
        );

    expect(favoriteIcon().fill, 0);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(toggleCount, 1);
    expect(favoriteIcon().fill, 1);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(toggleCount, 2);
    expect(favoriteIcon().fill, 0);
  });
}

class _TestRustLibApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(
        fore: (255, 0, 0, 0),
        accent: (255, 0, 0, 0),
      );
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
