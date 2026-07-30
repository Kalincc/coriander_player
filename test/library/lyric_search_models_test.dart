import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio audio(String path) => Audio(
      'Song',
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      100,
      90,
      'Lofty',
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('entry JSON round-trips without song metadata', () {
    const entry = LyricIndexEntry(
      audioPath: r'C:\music\song.flac',
      fingerprint: LyricFileFingerprint(
        audioModified: 100,
        sidecarPath: r'C:\music\song.lrc',
        sidecarModified: 120,
      ),
      lines: [LyricSearchLine(startMs: 12000, text: 'Hello 涓栫晫')],
    );
    expect(LyricIndexEntry.fromJson(entry.toJson()), entry);
    expect(entry.toJson().containsKey('title'), isFalse);
  });

  test('groups every case-insensitive match by song and removes duplicates',
      () {
    final song = audio(r'C:\music\song.flac');
    final entries = {
      song.path: LyricIndexEntry(
        audioPath: song.path,
        fingerprint: const LyricFileFingerprint(audioModified: 100),
        lines: const [
          LyricSearchLine(startMs: 30000, text: 'LOVE again'),
          LyricSearchLine(startMs: 10000, text: 'Love is here'),
          LyricSearchLine(startMs: 10000, text: 'Love is here'),
          LyricSearchLine(startMs: 20000, text: 'unrelated'),
        ],
      ),
    };

    final result = searchLyricEntries(
      query: ' love ',
      entries: entries,
      audios: [song],
    );

    expect(result, hasLength(1));
    expect(result.single.audio, same(song));
    expect(result.single.lines.map((line) => line.startMs), [10000, 30000]);
  });

  test('empty query and blank lyric lines do not match', () {
    final song = audio('song.flac');
    final entries = {
      song.path: LyricIndexEntry(
        audioPath: song.path,
        fingerprint: const LyricFileFingerprint(audioModified: 100),
        lines: const [LyricSearchLine(startMs: 0, text: '   ')],
      ),
    };
    expect(searchLyricEntries(query: ' ', entries: entries, audios: [song]),
        isEmpty);
    expect(searchLyricEntries(query: 'x', entries: entries, audios: [song]),
        isEmpty);
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
