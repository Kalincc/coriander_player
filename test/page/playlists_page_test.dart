import 'dart:typed_data';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/playlists_page.dart';
import 'package:coriander_player/page/playlist_detail_page.dart';
import 'package:coriander_player/page/uni_page.dart';
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

  testWidgets(
      'saved queue opens in saved order without changing other playlists',
      (tester) async {
    final originalPreference = AppPreference.instance.playlistDetailPagePref;
    final titlePreference =
        PagePreference(0, SortOrder.ascending, ContentView.list);
    AppPreference.instance.playlistDetailPagePref = titlePreference;
    addTearDown(() =>
        AppPreference.instance.playlistDetailPagePref = originalPreference);
    final zulu = _CoverAudio('D:/music/z.flac', null, title: 'Zulu');
    final alpha = _CoverAudio('D:/music/a.flac', null, title: 'Alpha');
    final snapshot = createPlaylistFromAudios('Queue snapshot', [zulu, alpha]);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlaylistDetailPage(playlist: snapshot))));
    await tester.pump();
    final page = tester.widget<UniPage<Audio>>(find.byType(UniPage<Audio>));
    expect(page.pref.sortMethod, 5);
    expect(page.sortMethods![page.pref.sortMethod].name, '歌单顺序');
    expect(page.contentList, [zulu, alpha]);
    expect(tester.getTopLeft(find.text('Zulu')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy));
    final reversed = List<Audio>.of(page.contentList);
    page.sortMethods!.last.method(reversed, SortOrder.decending);
    expect(reversed, [alpha, zulu]);
    expect(titlePreference.sortMethod, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaylistDetailPage(
                playlist: Playlist(
                    'Ordinary', {zulu.path: zulu, alpha.path: alpha})))));
    await tester.pump();
    expect(
        tester.widget<UniPage<Audio>>(find.byType(UniPage<Audio>)).contentList,
        [alpha, zulu]);
    expect(tester.takeException(), isNull);
  });
}

class _CoverAudio extends Audio {
  _CoverAudio(String path, this._testCover, {String? title})
      : super(title ?? path, 'Artist', 'Album', 1, 180, 320, 44100, path, 1, 1,
            'Lofty');

  final ImageProvider? _testCover;

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
