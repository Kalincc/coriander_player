import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path) => Audio(
      path,
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  testWidgets('reads items and plays an index through an injected service',
      (tester) async {
    final first = _audio('D:/music/first.flac');
    final second = _audio('D:/music/second.flac');
    final playback = _FakePlaybackService([first, second], currentIndex: 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CurrentPlaylistView(playbackService: playback)),
    ));

    expect(find.text(first.title), findsOneWidget);
    expect(find.text(second.title), findsOneWidget);
    expect(find.byTooltip('Clear queue'), findsNothing);
    expect(find.byTooltip('Remove from queue'), findsNothing);
    expect(find.byType(ReorderableListView), findsNothing);

    await tester.tap(find.text(second.title));
    expect(playback.playedIndexes, [1]);
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

class _FakePlaybackService extends ChangeNotifier
    implements PlaybackPlaylistController {
  _FakePlaybackService(List<Audio> items, {required this.currentIndex})
      : playlist = ValueNotifier(List.unmodifiable(items));

  @override
  final ValueNotifier<List<Audio>> playlist;

  final int currentIndex;

  final playedIndexes = <int>[];

  @override
  int get playlistIndex => currentIndex;

  @override
  void playIndexOfPlaylist(int audioIndex) {
    playedIndexes.add(audioIndex);
  }
}
