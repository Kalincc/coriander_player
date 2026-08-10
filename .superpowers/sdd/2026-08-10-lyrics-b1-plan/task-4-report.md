# Task 4 Report — Apply lyric offset across playback views

## Scope and baseline

- Worktree: `E:\codex_workplace\projects\coriander_player\.worktrees\lyrics-b1`
- Branch: `codex/lyrics-b1`
- Baseline commit: `89a3648 feat: add lyric display preferences and timing helpers`
- Baseline command:
  - `flutter test test/lyric/lyric_timing_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart`
  - Result: exit 0, 6 tests passed.

## TDD evidence

### RED 1 — timing boundaries and service preference refresh

Tests were added before production changes for:

- positive, negative, zero, and reset offsets against a pure `List<LyricLine>`;
- click-to-seek display timestamps, including clamping negative targets to zero and preserving the original line start;
- preference changes re-emitting the current lyric line;
- removal of the preference listener during `dispose`;
- a delegate fake that does not initialize audio hardware or a desktop lyric process.

Command:

`flutter test test/lyric/lyric_timing_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected failure (exit 1): compilation failed because `lyricLineIndexAt`, `LyricServiceDelegate`, and `LyricService.withDelegate` did not exist.

### GREEN 1 — timing and LyricService

Minimal implementation added `lyricLineIndexAt`, a production delegate boundary for `LyricService`, the read-only `lyricOffset` getter, unified `_emitLyricLine`, offset-aware current-line refresh, preference listening/removal, and load-path refreshes.

Command:

`flutter test test/lyric/lyric_timing_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Result: exit 0, 9 tests passed.

### RED 2 — view presentation and horizontal timing

Tests were added before view changes for:

- vertical lyric tiles obeying `showTranslation`;
- horizontal text using the shared presentation helper;
- horizontal scroll duration remaining `line.length - 2 * waitFor`, with no offset adjustment.

Command:

`flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart`

Expected failure (exit 1): compilation failed because `horizontalLyricText` and `horizontalLyricScrollDuration` did not exist.

### GREEN 2 — playback views

The first run after implementation exposed a test-fixture error: `LyricViewTile` contains an `InkWell`, while the fixture lacked a `Material` ancestor. The fixture was corrected without changing production behavior. The rerun completed with exit 0 and 11 tests passed.

## Implementation summary

- `LyricService`
  - applies `audioPosition - offset` without mutating lyric timestamps;
  - routes position changes, lyric loads, explicit recalculation, and preference changes through the same current-line calculation and `_emitLyricLine` path;
  - re-sends the original current `LyricLine` to the desktop lyric service when available;
  - removes its `NowPlayingPagePreference` listener in `dispose`;
  - supports an injected delegate for deterministic tests without real playback or process startup.
- Vertical lyrics
  - initial line uses `lyricLineIndexAt`;
  - click seek uses `lyricDisplayStart`, including zero clamping;
  - interlude animation uses the same offset-aware progress helper.
- Lyric tiles
  - word highlighting uses `lyricWordProgress`;
  - LRC and word-timed translations use `presentLyricLine` and the controller preference.
- Horizontal lyrics
  - visible text uses `presentLyricLine`;
  - preference changes refresh the current text immediately;
  - scroll duration remains based only on the original line duration;
  - the preference listener is removed in `dispose`.
- Out of scope was preserved: no translation control menu was added and `desktop_lyric_service.dart` message formatting was not changed.

## Verification

- `dart format` on all 8 affected Dart files: completed successfully.
- Required task tests: exit 0, 11 tests passed.
- Expanded regression command also included `lyric_presentation_test.dart` and `app_preference_test.dart`: exit 0, 23 tests passed.
- Full `flutter test`: exit 0, 98 tests passed.
- Affected-file analysis: no errors or warnings. Seven pre-existing info-level diagnostics remain in touched UI files (five `withOpacity` deprecations and two existing non-lowerCamelCase identifiers); the same constructs are present at baseline `89a3648`.
- `git diff --check`: exit 0 (only Git's configured LF-to-CRLF conversion notices were printed).

## Concerns

- The affected-file analyzer reports seven baseline info-level diagnostics. They are unrelated to Task 4 and were not mechanically rewritten to avoid expanding the patch.
- Tests intentionally use pure timing calculations, a small `LyricServiceDelegate` fake, and a non-main lyric tile. They do not start real audio devices, tickers tied to the singleton playback service, or desktop lyric processes.

## Review fix — playback-position rollback

- Finding: `_handlePositionChanged` started from the previous `_nextLyricLine` and only scanned forward, so a lower playback timestamp could not select an earlier lyric line.
- RED test: `position rollback re-emits the earlier offset-aware lyric line` uses only `_FakeLyricServiceDelegate`, a +1000 ms offset, and position events 11 s → 6 s. Before the fix, the targeted command exited 1 with actual emissions `[2]` instead of expected `[2, 1]`.
- Fix: position events and explicit refreshes now share `_updateCurrentLyricAt`, which absolutely recalculates `_nextLyricLine` from `lyricClockPosition(audioPosition, lyricOffset)` and the original line starts. Explicit refreshes force a re-emission; position events emit only when the absolute current line changes.
- GREEN command: `flutter test test/page/now_playing_page/lyric_scroll_positioner_test.dart --plain-name "position rollback re-emits the earlier offset-aware lyric line"` — exit 0, 1 test passed.
- Task command: `flutter test test/lyric/lyric_timing_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart` — exit 0, 12 tests passed.
- Analysis: `flutter analyze lib/play_service/lyric_service.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart` — exit 0, no issues found.
- Formatting: `dart format` / `dart format --output=none --set-exit-if-changed` for the two changed Dart files — exit 0.
- Diff check: `git diff --check` — exit 0.
- New commit: `fix: handle lyric position rollback` (the commit containing this report section).
- Additional concerns: none. The regression test does not initialize real audio or desktop lyric processes.
