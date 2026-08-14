# Album Grouping, Duration Charts, and Exclusive Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize the favorite tooltip, make albums default to artist-grouped browsing with group-local sorting, replace listening-report rankings with duration-based vertical charts, and make exclusive-mode failure recover safely to shared playback.

**Architecture:** Keep album grouping and output-mode switching as native-free domain logic with focused unit tests. Reuse the existing album cards, page preferences, navigation, artwork widgets, and BASS bindings; add only thin UI composition and a transactional playback adapter. Exclusive-mode fallback must rebuild a normal shared stream from a captured playback snapshot so a failed decode-only exclusive attempt never remains active.

**Tech Stack:** Flutter/Dart, Provider, existing Coriander UI components, `bass/basswasapi` FFI, Flutter test.

## Global Constraints

- Do not add chart, resampling, or native audio dependencies.
- Do not use `BASS_WASAPI_AUTOFORMAT`; exclusive mode requests the source format exactly.
- Preserve uncategorized and single-artist album filters.
- Collaborative albums appear in every participating artist group.
- Artist groups are always ordered by album count descending, then artist name ascending. The existing title/work-count choice and ascending/descending toggle affect albums inside each group only.
- Listening rankings use cumulative duration descending, then play count descending, then display name ascending.
- Exclusive failure must leave the real mode and UI in shared mode, restore path/position/volume/play-or-pause state, and surface a Chinese explanation.
- Do not change versions, publish releases, push commits, or install Rust/Cargo as part of this plan.

---

## Task 1: Localize the favorite tooltip

**Files:**

- Modify: `test/component/now_playing_favorite_button_test.dart`
- Modify: `lib/component/now_playing_favorite_button.dart`

- [ ] **Step 1: Write the failing tooltip assertions**

Extend the existing widget test so it finds the initial `Tooltip` and asserts `添加到喜欢的歌曲`, taps the button, pumps, and then asserts `从喜欢的歌曲中移除`.

- [ ] **Step 2: Run the focused test and confirm RED**

```powershell
flutter test --no-pub test/component/now_playing_favorite_button_test.dart
```

Expected: failure showing the current English tooltip.

- [ ] **Step 3: Replace only the user-facing strings**

```dart
tooltip: liked ? '从喜欢的歌曲中移除' : '添加到喜欢的歌曲',
```

- [ ] **Step 4: Re-run the focused test and confirm GREEN**

```powershell
flutter test --no-pub test/component/now_playing_favorite_button_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/component/now_playing_favorite_button.dart test/component/now_playing_favorite_button_test.dart
git commit -m "fix: localize liked song tooltip"
```

---

## Task 2: Define and test pure album grouping

**Files:**

- Create: `lib/page/album_grouping.dart`
- Create: `test/page/album_grouping_test.dart`

- [ ] **Step 1: Write tests for browse selection and group construction**

Cover these cases with small in-memory `Artist` and `Album` fixtures:

- `AlbumBrowseSelection.grouped()`, `.uncategorized()`, and `.artist(name)` are distinct typed selections.
- Artists are grouped by their linked albums.
- A collaborative album is present in both artist groups and is the same `Album` object.
- Groups sort by album count descending and then artist name ascending.
- A supplied album comparator affects only the albums within each group.
- Artists with no albums do not produce empty groups.

- [ ] **Step 2: Run the new test and confirm RED**

```powershell
flutter test --no-pub test/page/album_grouping_test.dart
```

Expected: compilation failure because the grouping API does not exist.

- [ ] **Step 3: Implement the smallest pure API**

```dart
enum AlbumBrowseMode { grouped, uncategorized, artist }

class AlbumBrowseSelection {
  const AlbumBrowseSelection.grouped()
      : mode = AlbumBrowseMode.grouped,
        artistName = null;
  const AlbumBrowseSelection.uncategorized()
      : mode = AlbumBrowseMode.uncategorized,
        artistName = null;
  const AlbumBrowseSelection.artist(String this.artistName)
      : mode = AlbumBrowseMode.artist;

  final AlbumBrowseMode mode;
  final String? artistName;
}

class AlbumArtistGroup {
  const AlbumArtistGroup({required this.artist, required this.albums});
  final Artist artist;
  final List<Album> albums;
}

List<AlbumArtistGroup> buildAlbumArtistGroups({
  required Iterable<Artist> artists,
  required Comparator<Album> sortAlbums,
}) {
  final groups = artists
      .map((artist) {
        final albums = artist.albumsMap.values.toList()..sort(sortAlbums);
        return AlbumArtistGroup(artist: artist, albums: albums);
      })
      .where((group) => group.albums.isNotEmpty)
      .toList();
  groups.sort((a, b) {
    final byCount = b.albums.length.compareTo(a.albums.length);
    return byCount != 0 ? byCount : a.artist.name.compareTo(b.artist.name);
  });
  return groups;
}
```

Adjust field names to the existing library model while preserving this contract.

- [ ] **Step 4: Run the test and confirm GREEN**

```powershell
flutter test --no-pub test/page/album_grouping_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/page/album_grouping.dart test/page/album_grouping_test.dart
git commit -m "feat: define artist album groups"
```

---

## Task 3: Add typed album selection and a lazy grouped view

**Files:**

- Modify: `lib/page/album_artist_filter.dart`
- Modify: `test/page/album_artist_filter_test.dart`
- Create: `lib/page/album_grouped_view.dart`
- Create: `test/page/album_grouped_view_test.dart`

- [ ] **Step 1: Update selector tests before its API**

Assert that the selector accepts and returns `AlbumBrowseSelection`, initially exposes `分类：按艺术家`, and offers:

- `分类：按艺术家`
- `分类：无分类`
- `艺术家：<name>` for each artist

Also preserve the existing artist-name filtering behavior in the dialog.

- [ ] **Step 2: Add failing grouped-view widget tests**

Create two groups with distinct albums and assert:

- both artist headings and album counts render;
- every album card is reachable;
- grid/list view follows the supplied `ContentView` preference;
- tapping an album invokes the existing navigation callback exactly once;
- a collaborative album can render once in each relevant group.

- [ ] **Step 3: Run the focused tests and confirm RED**

```powershell
flutter test --no-pub test/page/album_artist_filter_test.dart test/page/album_grouped_view_test.dart
```

- [ ] **Step 4: Implement typed selector choices**

Change the selector callback from `String?` to `AlbumBrowseSelection`. Keep the existing filtering helper functions, but make grouped and uncategorized explicit choices rather than overloading `null`.

- [ ] **Step 5: Implement one lazy scrollable grouped view**

Use one `CustomScrollView`. For each group append a heading sliver followed by either:

```dart
SliverFixedExtentList.builder(
  itemCount: group.albums.length,
  itemExtent: listItemExtent,
  itemBuilder: (context, index) => buildAlbumTile(group.albums[index]),
)
```

or a `SliverGrid.builder` using the repository's existing album grid delegate. Reuse existing album tile/card builders and navigation; do not nest scrolling lists.

- [ ] **Step 6: Re-run focused tests and confirm GREEN**

```powershell
flutter test --no-pub test/page/album_artist_filter_test.dart test/page/album_grouped_view_test.dart
```

- [ ] **Step 7: Commit**

```powershell
git add lib/page/album_artist_filter.dart lib/page/album_grouped_view.dart test/page/album_artist_filter_test.dart test/page/album_grouped_view_test.dart
git commit -m "feat: add grouped album browsing"
```

---

## Task 4: Make artist grouping the album-page default

**Files:**

- Modify: `lib/page/albums_page.dart`
- Create: `test/page/albums_page_test.dart`

- [ ] **Step 1: Write page-level behavior tests**

Build an `AudioLibrary` fixture and assert:

- the first render is grouped by artist without user interaction;
- groups use count-descending/name-ascending order;
- changing title/work-count and ascending/descending reorders albums inside groups but never reorders groups;
- selecting uncategorized returns to the existing flat `UniPage` behavior;
- selecting one artist returns the existing filtered flat behavior;
- list/grid preference is shared across grouped and flat modes.

- [ ] **Step 2: Run the page test and confirm RED**

```powershell
flutter test --no-pub test/page/albums_page_test.dart
```

- [ ] **Step 3: Add grouped state and branch rendering**

Initialize:

```dart
AlbumBrowseSelection _selection = const AlbumBrowseSelection.grouped();
```

For grouped selection, compose `PageScaffold` with the public `SortMethodComboBox`, `SortOrderSwitch`, and `ContentViewSwitch`, then pass the resolved group-local comparator into `buildAlbumArtistGroups` and render `AlbumGroupedView`. For uncategorized or a single artist, retain the existing `UniPage<Album>` path and predicates.

Keep one `PagePreference` source so the controls remain consistent between branches.

- [ ] **Step 4: Run album-page and adjacent tests**

```powershell
flutter test --no-pub test/page/albums_page_test.dart test/page/album_grouping_test.dart test/page/album_artist_filter_test.dart test/page/album_grouped_view_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/page/albums_page.dart test/page/albums_page_test.dart
git commit -m "feat: group albums by artist by default"
```

---

## Task 5: Rank listening-report entries by cumulative duration

**Files:**

- Modify: `test/library/listening_report_test.dart`
- Modify: `lib/library/listening_report.dart`

- [ ] **Step 1: Add duration-first ranking fixtures**

Include `Long` played once for 120 seconds and `Short` played twice for 60 seconds total. Assert `Long` ranks first. Add tie fixtures proving play count breaks equal-duration ties and name ascending breaks equal-duration/equal-count ties for songs, artists, and albums.

- [ ] **Step 2: Run the library test and confirm RED**

```powershell
flutter test --no-pub test/library/listening_report_test.dart
```

- [ ] **Step 3: Change the shared Top 10 comparator**

```dart
items.sort((a, b) {
  final byDuration = b.duration.compareTo(a.duration);
  if (byDuration != 0) return byDuration;
  final byPlayCount = b.playCount.compareTo(a.playCount);
  if (byPlayCount != 0) return byPlayCount;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return a.key.compareTo(b.key);
});
```

Use the actual entry field names and existing duration type.

- [ ] **Step 4: Re-run the focused test and confirm GREEN**

```powershell
flutter test --no-pub test/library/listening_report_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/library/listening_report.dart test/library/listening_report_test.dart
git commit -m "feat: rank listening reports by duration"
```

---

## Task 6: Build and integrate vertical duration charts

**Files:**

- Create: `lib/component/listening_duration_chart.dart`
- Create: `test/component/listening_duration_chart_test.dart`
- Modify: `lib/page/listening_report_page.dart`
- Modify: `test/page/listening_report_page_test.dart`

- [ ] **Step 1: Write failing component tests**

Define test items with known durations and assert:

- y-axis labels represent time, including zero and the maximum;
- bar height is proportional to duration, not play count;
- each cover sits directly above its bar endpoint;
- labels and play-count/accessibility text render;
- ten fixed-width columns can scroll horizontally in a narrow viewport;
- tapping a column calls only its supplied callback.

- [ ] **Step 2: Run the component test and confirm RED**

```powershell
flutter test --no-pub test/component/listening_duration_chart_test.dart
```

- [ ] **Step 3: Implement the dependency-free chart**

Use a small immutable item model:

```dart
class ListeningDurationChartItem {
  const ListeningDurationChartItem({
    required this.label,
    required this.listened,
    required this.playCount,
    required this.artwork,
    required this.onTap,
  });

  final String label;
  final Duration listened;
  final int playCount;
  final Future<ImageProvider?>? artwork;
  final VoidCallback onTap;
}
```

Lay out a fixed-height plot (about 220 logical pixels), four y-axis time labels, and a horizontally scrollable row of fixed-width columns (about 88 pixels each). Use `FractionallySizedBox(heightFactor: listened / maxListened)` for the bar. Put the existing `ArtworkThumbnail(size: 40)` immediately above the bar endpoint in the same column stack. Add a tooltip for truncated x-axis labels. Handle empty and all-zero input without division by zero.

- [ ] **Step 4: Replace the report page's horizontal ranking section**

Remove `_RankSection` and map each existing song/artist/album Top 10 list into an independent `ListeningDurationChart`. Keep three titled sections and the existing recent-history limit of 20. Preserve the current routes so chart taps only navigate to the song, artist, or album detail.

- [ ] **Step 5: Update integration tests**

Replace assertions against `rank-bar-*` width factors with chart item keys and proportional heights. Assert all three chart headings, covers, long-label tooltips, duration-axis labels, horizontal scrolling, and existing navigation destinations.

- [ ] **Step 6: Run report tests and confirm GREEN**

```powershell
flutter test --no-pub test/component/listening_duration_chart_test.dart test/page/listening_report_page_test.dart test/library/listening_report_test.dart
```

- [ ] **Step 7: Commit**

```powershell
git add lib/component/listening_duration_chart.dart lib/page/listening_report_page.dart test/component/listening_duration_chart_test.dart test/page/listening_report_page_test.dart
git commit -m "feat: chart listening time by rank"
```

---

## Task 7: Define a native-free output-mode transaction coordinator

**Files:**

- Create: `lib/src/bass/output_mode_switch.dart`
- Create: `test/src/bass/output_mode_switch_test.dart`

- [ ] **Step 1: Write coordinator call-order tests**

Use a fake operations adapter recording calls. Cover:

- shared → exclusive success: capture, rebuild exclusive; actual mode is exclusive;
- exclusive → shared: capture, rebuild shared, dispose WASAPI; actual mode is shared;
- exclusive failure: capture, rebuild exclusive throws typed failure, dispose partial WASAPI, rebuild shared; actual mode is shared and the failure is returned;
- paused input restores paused state; playing input restarts playing; idle/no-track does not fabricate a stream;
- exclusive attempt and shared rebuild both fail: return a distinct recovery failure while the actual mode remains shared;
- every fallback call order is exactly `capture → rebuild(true) → disposeWasapi → rebuild(false)`.

- [ ] **Step 2: Run the pure test and confirm RED**

```powershell
flutter test --no-pub test/src/bass/output_mode_switch_test.dart
```

- [ ] **Step 3: Implement typed transaction models**

Create:

```dart
enum PlaybackSnapshotState { idle, paused, playing }
enum ExclusiveFailureReason { unsupportedFormat, deviceUnavailable, initialization, recovery }

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.path,
    required this.position,
    required this.volume,
    required this.state,
  });
  final String? path;
  final Duration position;
  final double volume;
  final PlaybackSnapshotState state;
}

abstract interface class OutputModeOperations {
  PlaybackSnapshot captureSnapshot();
  void rebuildFromSnapshot(PlaybackSnapshot snapshot, {required bool exclusive});
  void disposeWasapi();
}

class OutputModeSwitchResult {
  const OutputModeSwitchResult({
    required this.actualExclusive,
    this.failureReason,
  });
  final bool actualExclusive;
  final ExclusiveFailureReason? failureReason;
}
```

Add a typed `WasapiInitializationException` carrying the mapped reason. Keep the coordinator synchronous to match the current BASS FFI calls.

- [ ] **Step 4: Implement the minimal coordinator**

It must never report exclusive after an exception. On exclusive failure it cleans partial WASAPI state before rebuilding shared mode from the same snapshot. Preserve the first failure reason unless shared recovery also fails, in which case return `recovery`.

- [ ] **Step 5: Run the pure test and confirm GREEN**

```powershell
flutter test --no-pub test/src/bass/output_mode_switch_test.dart
```

- [ ] **Step 6: Commit**

```powershell
git add lib/src/bass/output_mode_switch.dart test/src/bass/output_mode_switch_test.dart
git commit -m "feat: coordinate exclusive mode fallback"
```

---

## Task 8: Integrate transactional exclusive fallback and Chinese feedback

**Files:**

- Modify: `lib/src/bass/bass_player.dart`
- Modify: `lib/service/playback_service.dart`
- Create: `test/service/playback_output_mode_message_test.dart`
- Modify adjacent playback tests discovered under: `test/service/` and `test/src/bass/`

- [ ] **Step 1: Write UI-result mapping tests**

Extract or expose a pure message mapper and assert:

- success in exclusive mode has the current concise success behavior;
- unsupported source/device format explains in Chinese that exact exclusive format is unsupported and shared mode has been restored;
- device unavailable and initialization failures are Chinese and say shared mode was restored;
- recovery failure clearly says playback recovery failed and suggests reopening the track/output device;
- no raw `FormatException` or English BASS message reaches the snackbar.

- [ ] **Step 2: Run the new message test and confirm RED**

```powershell
flutter test --no-pub test/service/playback_output_mode_message_test.dart
```

- [ ] **Step 3: Make `BassPlayer` implement the operations adapter**

Track whether WASAPI initialized successfully with `_wasapiInitialized`. Make cleanup idempotent. Implement:

- `captureSnapshot()`: current file path, byte/time position converted to `Duration`, volume, and idle/paused/playing state;
- `rebuildFromSnapshot(snapshot, exclusive: false)`: create a normal playable shared BASS stream, restore position/volume, and start only when snapshot state was playing;
- `rebuildFromSnapshot(snapshot, exclusive: true)`: create the decode stream, request exact source format through WASAPI even when the prior state was paused, restore position/volume, and start WASAPI only when the prior state was playing;
- `disposeWasapi()`: stop/free only when initialized, then clear the flag.

Do not leave `_fstream` pointing to a decode-only stream after failed exclusive initialization.

- [ ] **Step 4: Map BASS/WASAPI error codes to typed reasons**

Translate `BASS_ERROR_FORMAT` to `unsupportedFormat`; map device-loss/unavailable codes to `deviceUnavailable`; map remaining initialization failures to `initialization`. Throw `WasapiInitializationException` internally instead of user-facing English `FormatException` text.

- [ ] **Step 5: Replace boolean mode switching with the coordinator result**

Have `BassPlayer.useExclusiveMode` return `OutputModeSwitchResult`. In `PlaybackService`, set the notifier from `result.actualExclusive`, never from the requested value. Show the mapped Chinese fallback message when `failureReason != null`.

- [ ] **Step 6: Add playback-state regressions**

In native-free tests/fakes, verify:

- a playing track resumes shared playback at approximately the same position after exclusive rejection;
- a paused track stays paused after fallback;
- volume survives the rebuild;
- the notifier remains `false` after fallback;
- a later ordinary play call uses a normal shared stream.

- [ ] **Step 7: Run output-mode and adjacent playback tests**

```powershell
flutter test --no-pub test/src/bass/output_mode_switch_test.dart test/service/playback_output_mode_message_test.dart
flutter test --no-pub test/service
```

If the repository has no native-free `test/service` aggregate compatible with this environment, run the specifically affected files and record that limitation rather than installing native toolchains.

- [ ] **Step 8: Commit**

```powershell
git add lib/src/bass/bass_player.dart lib/service/playback_service.dart test/service/playback_output_mode_message_test.dart test/src/bass/output_mode_switch_test.dart
git add test/service test/src/bass
git commit -m "fix: recover shared playback after exclusive errors"
```

Review the staged list before committing so unrelated user changes are not included.

---

## Task 9: Run final verification and prepare hardware validation

**Files:**

- Verify all files changed by Tasks 1–8
- Compare against: `docs/superpowers/specs/2026-08-14-album-report-exclusive-mode-design.md`

- [ ] **Step 1: Run the combined focused suite**

```powershell
flutter test --no-pub test/component/now_playing_favorite_button_test.dart test/page/album_grouping_test.dart test/page/album_artist_filter_test.dart test/page/album_grouped_view_test.dart test/page/albums_page_test.dart test/library/listening_report_test.dart test/component/listening_duration_chart_test.dart test/page/listening_report_page_test.dart test/src/bass/output_mode_switch_test.dart test/service/playback_output_mode_message_test.dart
```

- [ ] **Step 2: Run static and formatting checks**

```powershell
flutter analyze --no-fatal-infos lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
git status --short --branch
```

If existing unrelated analyzer findings remain, separate them from new findings and report exact output.

- [ ] **Step 3: Audit every approved requirement**

Check the implementation against the design spec, including group tie-breaking, collaborative albums, three independent charts, duration ranking, horizontal scrolling, cover placement, actual-mode notifier state, paused recovery, and Chinese failure text.

- [ ] **Step 4: Inspect commit scope**

```powershell
git log --oneline --decorate -10
git diff origin/main...HEAD --stat
git status --short
```

Confirm no dependency lockfile, DLL, generated artifact, version, or release metadata changed unintentionally.

- [ ] **Step 5: Hand off the physical-device check**

After software verification, test on the Lenovo Legion R7000 2021 with Sony WH-1000XM4 over the 3.5 mm cable using `银泰.m4a`:

1. Start shared playback and note position/volume.
2. Toggle exclusive mode.
3. If Realtek rejects 96 kHz/24-bit stereo ALAC output, confirm the Chinese message appears, the mode remains `Shrd`, and playback resumes without reopening the track.
4. Repeat while paused and confirm it stays paused.
5. Test a device-supported source format, if available, to confirm exclusive success still works.

- [ ] **Step 6: Stop before release operations**

Report test evidence and hardware outcome. Ask for explicit authorization before pushing or starting the non-publishing `.9` release workflow; never overwrite `v1.5.1-kalin.8`.
