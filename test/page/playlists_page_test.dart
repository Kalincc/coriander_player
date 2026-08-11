import 'dart:typed_data';

import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/playlists_page.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() {
    PLAYLISTS.clear();
  });

  tearDown(() {
    PLAYLISTS.clear();
  });

  testWidgets(
      'refreshes a mounted playlist row after its artwork source changes',
      (tester) async {
    final playlist = Playlist('Synced', {});
    final cover = MemoryImage(Uint8List.fromList([1]));
    final audio = _CoverAudio('D:/music/synced.flac', cover);
    PLAYLISTS.add(playlist);

    await tester.pumpWidget(const MaterialApp(home: PlaylistsPage()));
    expect(
      tester.widget<ArtworkThumbnail>(find.byType(ArtworkThumbnail)).image,
      isNull,
    );
    expect(
      (tester.widget<ListTile>(find.widgetWithText(ListTile, 'Synced')).subtitle
              as Text)
          .data,
      startsWith('0'),
    );

    addAudioToPlaylist(playlist, audio);
    await tester.pump();

    final artwork = tester.widget<ArtworkThumbnail>(
      find.byType(ArtworkThumbnail),
    );
    expect(await artwork.image, same(cover));
    expect(
      (tester.widget<ListTile>(find.widgetWithText(ListTile, 'Synced')).subtitle
              as Text)
          .data,
      startsWith('1'),
    );
  });
}

class _CoverAudio extends Audio {
  _CoverAudio(String path, this._testCover)
      : super(path, 'Artist', 'Album', 1, 180, 320, 44100, path, 1, 1, 'Lofty');

  final ImageProvider _testCover;

  @override
  Future<ImageProvider?> get cover => Future.value(_testCover);
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
