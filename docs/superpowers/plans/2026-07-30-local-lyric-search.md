# Local Lyric Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fast, persistent, incremental search over embedded and sidecar local lyrics, with grouped non-playing results in the existing search page.

**Architecture:** Keep `index.json` unchanged and add a Dart-owned `lyric_search_index.json`. A testable `LyricSearchIndex` service loads cached entries immediately, refreshes changed files in a bounded background worker pool, and exposes synchronous in-memory search plus progress notifications. The search UI receives a query string, combines current metadata results with indexed lyric matches, and uses a dedicated non-playing result tile.

**Tech Stack:** Flutter/Dart, `ChangeNotifier`, `dart:io`, `dart:convert`, existing Rust lyric reader through `Lrc.fromAudioPath`, `go_router`, `flutter_test`.

## Global Constraints

- Target the Windows version of Coriander Player.
- Search embedded lyrics and same-name local LRC files only; never request, download, or cache online lyrics.
- Do not change BASS, WASAPI, playback modes, the playback queue, or `desktop_lyric`.
- Store the new index separately from `index.json` at `Documents/coriander_player/lyric_search_index.json`.
- Do not add a real-time file watcher; refresh on application start and after a music-library update.
- Clicking a lyric result locates the song in the music page without playing, seeking, or changing the queue.
- One song produces one result group containing every matching lyric line.
- Add no new package dependency.

## File Map

- Create `lib/library/lyric_search_models.dart`: immutable JSON models and pure matching functions.
- Create `lib/library/lyric_search_index.dart`: cache loading, bounded incremental synchronization, progress, search, and production file adapters.
- Create `lib/component/lyric_search_result_tile.dart`: grouped result rendering and query highlighting with a callback-only navigation boundary.
- Modify `lib/page/updating_page.dart`: load cached lyrics before navigation and start non-blocking synchronization.
- Modify `lib/page/welcoming_page.dart`: initialize lyric search after the first music-library build.
- Modify `lib/page/settings_page/other_settings.dart`: synchronize lyrics after the user rebuilds the configured folders.
- Modify `lib/page/search_page/search_page.dart`: send a query string to the results route and include lyric matches in `UnionSearchResult`.
- Modify `lib/page/search_page/search_result_page.dart`: own live search state, add the lyric tab and progress/empty states, and locate songs.
- Modify `lib/entry.dart`: pass the query string into `SearchResultPage`.
- Create `test/library/lyric_search_models_test.dart`.
- Create `test/library/lyric_search_index_test.dart`.
- Create `test/component/lyric_search_result_tile_test.dart`.
- Create `test/page/search_result_page_test.dart`.

---

### Task 1: Pure lyric index models and matching

**Files:**
- Create: `lib/library/lyric_search_models.dart`
- Test: `test/library/lyric_search_models_test.dart`

**Interfaces:**
- Consumes: `Audio` from `lib/library/audio_library.dart`.
- Produces: `LyricSearchLine`, `LyricFileFingerprint`, `LyricIndexEntry`, `LyricSearchMatch`, and `searchLyricEntries({required String query, required Map<String, LyricIndexEntry> entries, required Iterable<Audio> audios})`.

- [ ] **Step 1: Write failing serialization and matching tests**

```dart
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:flutter_test/flutter_test.dart';

Audio audio(String path) => Audio(
      'Song', 'Artist', 'Album', 1, 180, 320, 44100,
      path, 100, 90, 'Lofty',
    );

void main() {
  test('entry JSON round-trips without song metadata', () {
    final entry = LyricIndexEntry(
      audioPath: r'C:\music\song.flac',
      fingerprint: const LyricFileFingerprint(
        audioModified: 100,
        sidecarPath: r'C:\music\song.lrc',
        sidecarModified: 120,
      ),
      lines: const [LyricSearchLine(startMs: 12000, text: 'Hello 世界')],
    );
    expect(LyricIndexEntry.fromJson(entry.toJson()), entry);
    expect(entry.toJson().containsKey('title'), isFalse);
  });

  test('groups every case-insensitive match by song and removes duplicates', () {
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
    expect(searchLyricEntries(query: ' ', entries: entries, audios: [song]), isEmpty);
    expect(searchLyricEntries(query: 'x', entries: entries, audios: [song]), isEmpty);
  });
}
```

- [ ] **Step 2: Run the model tests and confirm the missing-library failure**

Run: `flutter test test/library/lyric_search_models_test.dart`

Expected: FAIL because `lyric_search_models.dart` and its types do not exist.

- [ ] **Step 3: Implement immutable models and the pure matcher**

Use these exact public signatures:

```dart
@immutable
class LyricSearchLine {
  final int startMs;
  final String text;
  const LyricSearchLine({required this.startMs, required this.text});
  String get normalizedText => text.toLowerCase();
  Map<String, Object> toJson() => {'startMs': startMs, 'text': text};
  factory LyricSearchLine.fromJson(Map<String, dynamic> json) =>
      LyricSearchLine(startMs: json['startMs'] as int, text: json['text'] as String);
  // Implement value equality and hashCode over startMs and text.
}

@immutable
class LyricFileFingerprint {
  final int audioModified;
  final String? sidecarPath;
  final int? sidecarModified;
  const LyricFileFingerprint({
    required this.audioModified,
    this.sidecarPath,
    this.sidecarModified,
  });
  // Implement toJson, fromJson, value equality, and hashCode.
}

@immutable
class LyricIndexEntry {
  final String audioPath;
  final LyricFileFingerprint fingerprint;
  final List<LyricSearchLine> lines;
  const LyricIndexEntry({
    required this.audioPath,
    required this.fingerprint,
    required this.lines,
  });
  // Implement toJson, fromJson, value equality, and hashCode.
}

@immutable
class LyricSearchMatch {
  final Audio audio;
  final List<LyricSearchLine> lines;
  const LyricSearchMatch({required this.audio, required this.lines});
}
```

Implement `searchLyricEntries` by trimming and lowercasing the query, joining entries to current `Audio` instances by path, discarding blank lines, deduplicating with `(startMs, text)`, and sorting matches by `startMs`.

- [ ] **Step 4: Run the model tests**

Run: `flutter test test/library/lyric_search_models_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the pure model layer**

```powershell
git add lib/library/lyric_search_models.dart test/library/lyric_search_models_test.dart
git commit -m "feat: add local lyric search models"
```

---

### Task 2: Persistent incremental lyric index service

**Files:**
- Create: `lib/library/lyric_search_index.dart`
- Test: `test/library/lyric_search_index_test.dart`

**Interfaces:**
- Consumes: all Task 1 models; injected `readIndex`, `writeIndex`, `fingerprintFor`, and `lyricLinesFor` callbacks.
- Produces: `LyricIndexProgress`, `LyricSearchIndex.load()`, `LyricSearchIndex.sync(Iterable<Audio>)`, and `LyricSearchIndex.search(String, Iterable<Audio>)`. Task 3 adds the production singleton.

- [ ] **Step 1: Write failing service tests with in-memory adapters**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_index.dart';
import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:flutter_test/flutter_test.dart';

Audio makeAudio(String path, int modified) => Audio(
      path, 'Artist', 'Album', 1, 10, null, null,
      path, modified, modified, 'Lofty',
    );

void main() {
  test('sync reads only new or changed songs and removes deleted songs', () async {
    String? persisted;
    final loads = <String>[];
    final fingerprints = <String, LyricFileFingerprint>{
      'a.flac': const LyricFileFingerprint(audioModified: 1),
      'b.flac': const LyricFileFingerprint(audioModified: 1),
    };
    final index = LyricSearchIndex(
      readIndex: () async => persisted,
      writeIndex: (contents) async => persisted = contents,
      fingerprintFor: (audio) async => fingerprints[audio.path]!,
      lyricLinesFor: (audio) async {
        loads.add(audio.path);
        return [LyricSearchLine(startMs: 0, text: audio.path)];
      },
      workerCount: 2,
    );

    await index.load();
    await index.sync([makeAudio('a.flac', 1), makeAudio('b.flac', 1)]);
    expect(loads, containsAll(['a.flac', 'b.flac']));

    loads.clear();
    await index.sync([makeAudio('a.flac', 1)]);
    expect(loads, isEmpty);
    expect(index.entries.keys, ['a.flac']);

    fingerprints['a.flac'] = const LyricFileFingerprint(audioModified: 2);
    await index.sync([makeAudio('a.flac', 2)]);
    expect(loads, ['a.flac']);
    expect(jsonDecode(persisted!)['version'], 1);
  });

  test('corrupt JSON resets to an empty usable index', () async {
    final index = LyricSearchIndex(
      readIndex: () async => '{broken',
      writeIndex: (_) async {},
      fingerprintFor: (_) async => const LyricFileFingerprint(audioModified: 1),
      lyricLinesFor: (_) async => const [],
    );
    await index.load();
    expect(index.entries, isEmpty);
    expect(index.progress.error, isNotNull);
  });

  test('one lyric read failure does not stop remaining songs', () async {
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async {},
      fingerprintFor: (audio) async => LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (audio) async {
        if (audio.path == 'bad.flac') throw const FormatException('bad lyric');
        return const [LyricSearchLine(startMs: 1, text: 'ok')];
      },
    );
    await index.load();
    await index.sync([makeAudio('bad.flac', 1), makeAudio('good.flac', 1)]);
    expect(index.entries['good.flac']!.lines.single.text, 'ok');
    expect(index.progress.processed, 2);
  });

  test('save failure keeps searchable in-memory entries', () async {
    final index = LyricSearchIndex(
      readIndex: () async => null,
      writeIndex: (_) async => throw const FileSystemException('disk full'),
      fingerprintFor: (audio) async => LyricFileFingerprint(audioModified: audio.modified),
      lyricLinesFor: (_) async => const [LyricSearchLine(startMs: 1, text: 'needle')],
    );
    await index.load();
    final song = makeAudio('song.flac', 1);
    await index.sync([song]);
    expect(index.search('needle', [song]), hasLength(1));
    expect(index.progress.error, isNotNull);
  });
}
```

- [ ] **Step 2: Run the service tests and verify they fail**

Run: `flutter test test/library/lyric_search_index_test.dart`

Expected: FAIL because `LyricSearchIndex` is undefined.

- [ ] **Step 3: Implement the service API and versioned JSON envelope**

```dart
typedef ReadLyricIndex = Future<String?> Function();
typedef WriteLyricIndex = Future<void> Function(String contents);
typedef ReadLyricFingerprint = Future<LyricFileFingerprint> Function(Audio audio);
typedef ReadLocalLyricLines = Future<List<LyricSearchLine>> Function(Audio audio);

@immutable
class LyricIndexProgress {
  final int processed;
  final int total;
  final bool isSyncing;
  final Object? error;
  const LyricIndexProgress({
    this.processed = 0,
    this.total = 0,
    this.isSyncing = false,
    this.error,
  });
}

class LyricSearchIndex extends ChangeNotifier {
  static const int formatVersion = 1;

  final ReadLyricIndex readIndex;
  final WriteLyricIndex writeIndex;
  final ReadLyricFingerprint fingerprintFor;
  final ReadLocalLyricLines lyricLinesFor;
  final int workerCount;

  final Map<String, LyricIndexEntry> entries = {};
  LyricIndexProgress progress = const LyricIndexProgress();

  LyricSearchIndex({
    required this.readIndex,
    required this.writeIndex,
    required this.fingerprintFor,
    required this.lyricLinesFor,
    this.workerCount = 4,
  });
}
```

Add the concrete methods `Future<void> load()`, `Future<void> sync(Iterable<Audio> audios)`, and `List<LyricSearchMatch> search(String query, Iterable<Audio> audios)`. Guard `load` with a private `_loaded` flag so repeated library refresh entry points never overwrite an already loaded in-memory index. `load` accepts only the envelope `{'version': 1, 'entries': <String, dynamic>{...}}`; missing input produces an empty index, and malformed/version-mismatched input clears entries, records the caught object in `progress.error`, marks the service loaded, and notifies listeners. `search` delegates directly to `searchLyricEntries`.

For `sync`, snapshot the audio list, remove paths no longer present, probe every fingerprint, enqueue only new/changed entries, and process the queue with `min(workerCount, queue.length)` workers. Catch errors per song. Update `progress` and notify listeners every 25 processed songs and at completion. Serialize exactly `{'version': 1, 'entries': {path: entry.toJson()}}`. Catch `writeIndex` errors after retaining the updated in-memory map.

- [ ] **Step 4: Run service and model tests**

Run: `flutter test test/library/lyric_search_index_test.dart test/library/lyric_search_models_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the testable index core**

```powershell
git add lib/library/lyric_search_index.dart test/library/lyric_search_index_test.dart
git commit -m "feat: add incremental lyric search index"
```

---

### Task 3: Production file adapters and startup synchronization

**Files:**
- Modify: `lib/library/lyric_search_index.dart`
- Modify: `lib/page/updating_page.dart:1-80`
- Modify: `lib/page/welcoming_page.dart:85-97`
- Modify: `lib/page/settings_page/other_settings.dart:151-165`
- Test: `test/library/lyric_search_index_test.dart`

**Interfaces:**
- Consumes: `getAppDataDir()`, `Lrc.fromAudioPath(Audio)`, `path.setExtension`, and `AudioLibrary.instance.audioCollection`.
- Produces: a working `LyricSearchIndex.defaults()`, `LyricSearchIndex.refreshCurrentLibrary()`, and non-blocking synchronization after every music-library build/update path.

- [ ] **Step 1: Add failing tests for the sidecar fingerprint and atomic store**

Add tests using `Directory.systemTemp.createTemp('coriander_lyric_index_')`: create `song.flac` and `song.lrc`, call the public test-visible helpers `readLocalLyricFingerprint(audio)` and `writeLyricIndexAtomically(directory, contents)`, and assert that changing/deleting `song.lrc` changes `sidecarModified`/clears `sidecarPath`, while a successful write leaves only valid JSON at `lyric_search_index.json` and no `.tmp` file. Delete the temporary directory in `addTearDown`.

- [ ] **Step 2: Run the adapter tests and verify missing-helper failures**

Run: `flutter test test/library/lyric_search_index_test.dart`

Expected: FAIL because the two production helpers are undefined.

- [ ] **Step 3: Implement production adapters**

```dart
Future<LyricFileFingerprint> readLocalLyricFingerprint(Audio audio) async {
  final sidecarPath = path.setExtension(audio.path, '.lrc');
  final sidecar = File(sidecarPath);
  final exists = await sidecar.exists();
  return LyricFileFingerprint(
    audioModified: audio.modified,
    sidecarPath: exists ? sidecarPath : null,
    sidecarModified: exists
        ? (await sidecar.lastModified()).millisecondsSinceEpoch
        : null,
  );
}

Future<List<LyricSearchLine>> readLocalLyricLines(Audio audio) async {
  final lyric = await Lrc.fromAudioPath(audio);
  if (lyric == null) return const [];
  return lyric.lines
      .whereType<UnsyncLyricLine>()
      .where((line) => line.content.trim().isNotEmpty)
      .map((line) => LyricSearchLine(
            startMs: line.start.inMilliseconds,
            text: line.content,
          ))
      .toList(growable: false);
}
```

Implement `writeLyricIndexAtomically` with `lyric_search_index.json.tmp` plus a `.bak` rollback: write and flush the temporary file; rename the current file to `.bak`; rename `.tmp` to the final path; delete `.bak`; on failure restore `.bak` and rethrow. `LyricSearchIndex.defaults()` must bind these helpers and read from the same app-data directory returned by `getAppDataDir()`.

Add the production singleton and factory with these bindings:

```dart
static final LyricSearchIndex instance = LyricSearchIndex.defaults();

factory LyricSearchIndex.defaults() => LyricSearchIndex(
      readIndex: () async {
        final directory = await getAppDataDir();
        final file = File(path.join(directory.path, 'lyric_search_index.json'));
        return await file.exists() ? file.readAsString() : null;
      },
      writeIndex: (contents) async {
        final directory = await getAppDataDir();
        await writeLyricIndexAtomically(directory, contents);
      },
      fingerprintFor: readLocalLyricFingerprint,
      lyricLinesFor: readLocalLyricLines,
      workerCount: 4,
    );
```

Add this coordinator method to the service so UI entry points wait only for cached data, not the full refresh:

```dart
Future<void> refreshCurrentLibrary() async {
  await load();
  unawaited(sync(AudioLibrary.instance.audioCollection));
}
```

- [ ] **Step 4: Wire startup without blocking navigation on the full refresh**

In `whenIndexUpdated`, await cached index loading after `AudioLibrary.initFromIndex()` finishes, then let the service start synchronization without awaiting the full refresh:

```dart
await Future.wait([
  AudioLibrary.initFromIndex(),
  readPlaylists(),
  readLyricSources(),
]);
await LyricSearchIndex.instance.refreshCurrentLibrary();
```

Import `lyric_search_index.dart`; keep navigation and playback initialization unchanged. Add the same awaited `refreshCurrentLibrary()` call after `AudioLibrary.initFromIndex()` in `WelcomingPage.whenIndexBuilt` and in the folder rebuild callback in `settings_page/other_settings.dart`. Do not add it to the artist-separator editor: that path recreates Dart artist objects without changing lyric files, and searches already join cache entries to the current `Audio` objects by path.

- [ ] **Step 5: Run adapter and startup static checks**

Run: `flutter test test/library/lyric_search_index_test.dart`

Expected: PASS.

Run: `flutter analyze lib/library/lyric_search_index.dart lib/page/updating_page.dart`

Expected: no diagnostics.

- [ ] **Step 6: Commit production synchronization**

```powershell
git add lib/library/lyric_search_index.dart lib/page/updating_page.dart lib/page/welcoming_page.dart lib/page/settings_page/other_settings.dart test/library/lyric_search_index_test.dart
git commit -m "feat: persist and refresh local lyric index"
```

---

### Task 4: Combine metadata and lyric search state

**Files:**
- Modify: `lib/page/search_page/search_page.dart:8-103`
- Modify: `lib/page/search_page/search_result_page.dart:11-104`
- Modify: `lib/entry.dart:185-205`
- Test: `test/page/search_result_page_test.dart`

**Interfaces:**
- Consumes: `LyricSearchIndex.search`, `AudioLibrary`, and a route `extra` containing the submitted `String` query.
- Produces: `UnionSearchResult.lyrics`, `UnionSearchResult.search(String, {LyricSearchIndex? lyricIndex})`, and `SearchResultPage(initialQuery:, lyricIndex:)`.

- [ ] **Step 1: Write failing result-state tests**

Create a small injected `LyricSearchIndex`, add its test `Audio` to the public collections on `AudioLibrary.instance`, and restore those collections in `tearDown`. Assert that `UnionSearchResult.search('needle', lyricIndex: index)` returns normal title results plus one `lyrics` group. Add a widget test that pumps `SearchResultPage(initialQuery: 'needle', lyricIndex: index)`, asserts five tabs in the order `所有, 音乐, 歌词, 艺术家, 专辑`, then changes the injected fingerprint/line callbacks, calls `await index.sync(...)`, pumps, and verifies the unchanged query refreshes from the service's normal notification path.

- [ ] **Step 2: Run the result-state tests and verify failures**

Run: `flutter test test/page/search_result_page_test.dart`

Expected: FAIL because the lyric result field, injected index, and fifth tab do not exist.

- [ ] **Step 3: Extend `UnionSearchResult` and change route input to a query string**

```dart
class UnionSearchResult {
  final String query;
  final List<Audio> audios = [];
  final List<Artist> artists = [];
  final List<Album> album = [];
  final List<LyricSearchMatch> lyrics = [];

  UnionSearchResult(this.query);

  static UnionSearchResult search(
    String query, {
    LyricSearchIndex? lyricIndex,
  }) {
    final result = UnionSearchResult(query);
    result.lyrics.addAll(
      (lyricIndex ?? LyricSearchIndex.instance)
          .search(query, AudioLibrary.instance.audioCollection),
    );
    return result;
  }
}
```

Change both search text fields to trim and reject empty input. The initial page pushes `extra: query`; `entry.dart` reads `state.extra as String` and constructs `SearchResultPage(initialQuery: query)`.

- [ ] **Step 4: Make `SearchResultPage` refresh safely from index notifications**

Add nullable injection for tests:

```dart
final String initialQuery;
final LyricSearchIndex? lyricIndex;
const SearchResultPage({
  super.key,
  required this.initialQuery,
  this.lyricIndex,
});
```

In state, resolve `index = widget.lyricIndex ?? LyricSearchIndex.instance`, initialize the controller/result from `initialQuery`, add an index listener in `initState`, and remove it in `dispose`. `_runSearch(query)` must read the current controller text before replacing the `ValueNotifier`, so an index notification cannot restore an older query. Dispose both the text controller and result notifier. Set `DefaultTabController.length` to 5 and add `lyrics("歌词")` between music and artist.

- [ ] **Step 5: Run the result-state tests**

Run: `flutter test test/page/search_result_page_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit search state integration**

```powershell
git add lib/page/search_page/search_page.dart lib/page/search_page/search_result_page.dart lib/entry.dart test/page/search_result_page_test.dart
git commit -m "feat: integrate lyric matches into search"
```

---

### Task 5: Grouped lyric result UI and locate-only navigation

**Files:**
- Create: `lib/component/lyric_search_result_tile.dart`
- Modify: `lib/page/search_page/search_result_page.dart:106-204`
- Test: `test/component/lyric_search_result_tile_test.dart`
- Test: `test/page/search_result_page_test.dart`

**Interfaces:**
- Consumes: `LyricSearchMatch`, the submitted query, and a `VoidCallback onLocate`.
- Produces: `LyricSearchResultTile(match:, query:, onLocate:)`, `formatLyricTimestamp(int)`, and lyric slivers for “所有” and “歌词”.

- [ ] **Step 1: Write failing tile tests**

Pump a tile with one `Audio`, three matching lines, and an incrementing `onLocate`. Assert song title, artist/album, all three lyrics, `02:05` formatting for `125000` ms, highlighted `TextSpan`s for a case-insensitive query, and one callback invocation after tapping the song header, a lyric row, and the location button in separate test cases. Assert the widget source does not import `play_service.dart` by keeping playback outside this component boundary.

- [ ] **Step 2: Run the tile tests and verify the missing-widget failure**

Run: `flutter test test/component/lyric_search_result_tile_test.dart`

Expected: FAIL because `LyricSearchResultTile` is undefined.

- [ ] **Step 3: Implement the callback-only result tile**

```dart
String formatLyricTimestamp(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class LyricSearchResultTile extends StatelessWidget {
  final LyricSearchMatch match;
  final String query;
  final VoidCallback onLocate;
  const LyricSearchResultTile({
    super.key,
    required this.match,
    required this.query,
    required this.onLocate,
  });
}
```

Build one song header followed by a widget for every `line` in `match.lines`. Use `RegExp(RegExp.escape(query.trim()), caseSensitive: false).allMatches(line.text)` to split each line into normal and highlighted `TextSpan`s. Wrap the header, each lyric row, and the location icon in separate `InkWell`/`IconButton` surfaces that all invoke `onLocate`. Use the existing cover-loading visual pattern, but do not reuse `AudioTile` because its primary tap starts playback.

- [ ] **Step 4: Add lyric content, progress, and empty state to the results page**

Add `buildLyricResultContent`. Each tile passes:

```dart
onLocate: () => context.push(app_paths.AUDIOS_PAGE, extra: match.audio),
```

In “所有”, insert non-empty lyric results after music and before artist. In “歌词”, show all lyric groups. When empty and not syncing, show `未找到匹配的本地歌词`. When syncing, add a non-blocking header using `index.progress`: `正在建立本地歌词索引：已处理 ${processed}/${total}`. Change both hint strings to `搜索歌曲、艺术家、专辑、歌词`.

- [ ] **Step 5: Run component and page tests**

Run: `flutter test test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart`

Expected: PASS, including the assertion that locating does not invoke a playback callback.

- [ ] **Step 6: Commit grouped lyric results**

```powershell
git add lib/component/lyric_search_result_tile.dart lib/page/search_page/search_result_page.dart test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart
git commit -m "feat: show grouped local lyric results"
```

---

### Task 6: Lyric search regression and Windows verification

**Files:**
- Modify only files needed to fix failures found by the commands below.

**Interfaces:**
- Consumes: the complete lyric index and search UI from Tasks 1–5.
- Produces: a release-buildable, regression-tested local lyric search feature.

- [ ] **Step 1: Run focused tests**

Run: `flutter test test/library/lyric_search_models_test.dart test/library/lyric_search_index_test.dart test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart`

Expected: all tests PASS.

- [ ] **Step 2: Run project-wide static analysis and tests**

Run: `flutter analyze`

Expected: no diagnostics.

Run: `flutter test`

Expected: all tests PASS.

- [ ] **Step 3: Check Rust and build Windows Release**

Run: `cargo check --manifest-path rust/Cargo.toml`

Expected: exit code 0.

Run: `flutter build windows --release`

Expected: exit code 0 and an executable under `build/windows/x64/runner/Release`.

- [ ] **Step 4: Perform manual acceptance with controlled fixtures**

Use one song with embedded LRC, one with a same-name `.lrc`, one with no local lyrics, and two songs sharing the same matching phrase. Verify first-build progress, restart reuse, sidecar modification after restart, grouped complete matches, query highlighting, “所有”/“歌词” tabs, and locate-only navigation. Confirm the currently playing song, queue, and position remain unchanged after every result click.

- [ ] **Step 5: Confirm the verification task leaves a clean worktree**

```powershell
git status --short
```

Expected: no output. This verification-only task creates no commit. If a command exposes a defect, return to the owning task, add a focused failing test there, apply the fix, and use that task's explicit file list and commit command.
