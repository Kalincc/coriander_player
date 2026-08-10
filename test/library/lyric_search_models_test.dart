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

  test('line JSON round-trips translations and persisted search forms', () {
    final line = LyricSearchLine(
      startMs: 12000,
      text: '我愛你',
      translation: 'I love you',
      searchForms: const [
        '我愛你',
        '我爱你',
        'wo ai ni',
        'woaini',
        'i love you',
      ],
    );

    expect(line.toJson(), {
      'startMs': 12000,
      'text': '我愛你',
      'translation': 'I love you',
      'searchForms': [
        '我愛你',
        '我爱你',
        'wo ai ni',
        'woaini',
        'i love you',
      ],
    });
    expect(LyricSearchLine.fromJson(line.toJson()), line);
  });

  test('legacy line JSON calculates search forms when fields are absent', () {
    final line = LyricSearchLine.fromJson({
      'startMs': 12000,
      'text': '我愛你',
    });

    expect(line.translation, isNull);
    expect(line.searchForms, ['我愛你', '我爱你', 'wo ai ni', 'woaini']);
  });

  test('entry JSON round-trips without song metadata', () {
    final entry = LyricIndexEntry(
      audioPath: r'C:\music\song.flac',
      fingerprint: const LyricFileFingerprint(
        audioModified: 100,
        sidecarPath: r'C:\music\song.lrc',
        sidecarModified: 120,
      ),
      lines: const [LyricSearchLine(startMs: 12000, text: 'Hello 涓栫晫')],
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

  test('matches traditional lyrics, simplified text, pinyin, and translation',
      () {
    final song = audio('song.flac');
    final originalLine = LyricSearchLine(
      startMs: 1500,
      text: '我愛你',
      translation: 'I love you',
    );
    final entries = {
      song.path: LyricIndexEntry(
        audioPath: song.path,
        fingerprint: const LyricFileFingerprint(audioModified: 100),
        lines: [originalLine],
      ),
    };

    for (final query in ['我愛你', '我爱你', 'wo ai ni', 'i love you']) {
      final result = searchLyricEntries(
        query: query,
        entries: entries,
        audios: [song],
      );

      expect(result, hasLength(1), reason: query);
      expect(result.single.audio, same(song), reason: query);
      expect(result.single.lines, [originalLine], reason: query);
    }
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

  test('entry snapshots lyric lines as unmodifiable', () {
    final sourceLines = [
      const LyricSearchLine(startMs: 1000, text: 'first line'),
    ];
    final entry = LyricIndexEntry(
      audioPath: 'song.flac',
      fingerprint: const LyricFileFingerprint(audioModified: 100),
      lines: sourceLines,
    );

    sourceLines.add(const LyricSearchLine(startMs: 2000, text: 'second line'));

    expect(entry.lines,
        [const LyricSearchLine(startMs: 1000, text: 'first line')]);
    expect(
      () => entry.lines.add(
        const LyricSearchLine(startMs: 3000, text: 'third line'),
      ),
      throwsUnsupportedError,
    );
  });

  test('match snapshots lyric lines as unmodifiable', () {
    final sourceLines = [
      const LyricSearchLine(startMs: 1000, text: 'first line'),
    ];
    final match = LyricSearchMatch(
      audio: audio('song.flac'),
      lines: sourceLines,
    );

    sourceLines.add(const LyricSearchLine(startMs: 2000, text: 'second line'));

    expect(match.lines,
        [const LyricSearchLine(startMs: 1000, text: 'first line')]);
    expect(
      () => match.lines.add(
        const LyricSearchLine(startMs: 3000, text: 'third line'),
      ),
      throwsUnsupportedError,
    );
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
