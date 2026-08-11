import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playlist.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
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

  setUp(() {
    PLAYLISTS.clear();
  });

  test('adds only new selected songs, revises once per add, and saves once',
      () async {
    final existing = _audio('D:/music/existing.flac');
    final added = _audio('D:/music/added.flac');
    final playlist = Playlist('regular', {existing.path: existing});
    final revision = playlistRevision.value;
    var saves = 0;

    expect(
      await addAudiosToPlaylist(
        playlist,
        [existing, added],
        persist: () async => saves++,
      ),
      1,
    );
    expect(playlist.audios.keys, [existing.path, added.path]);
    expect(playlistRevision.value, revision + 1);
    expect(saves, 1);

    expect(
      await addAudiosToPlaylist(
        playlist,
        [existing, added],
        persist: () async => saves++,
      ),
      0,
    );
    expect(playlistRevision.value, revision + 1);
    expect(saves, 1);
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
