# Task 5 Report — lyric controls and unified translation display

## Scope and baseline

- Worktree: `E:\codex_workplace\projects\coriander_player\.worktrees\lyrics-b1`
- Branch: `codex/lyrics-b1`
- Baseline: `ed410fb fix: handle lyric position rollback`
- Baseline command:
  - `flutter test test/lyric/lyric_presentation_test.dart test/app_preference_test.dart test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart`
  - Result: exit 0, 19 tests passed.

## TDD evidence

### RED — controller and presentation consumers

Tests were added before production changes for:

- `LyricViewController` offset changes in 100 ms steps, both boundaries, reset, translation toggling, listener notification, preference updates, and asynchronous persistence;
- source-preview current-line selection through the offset-aware lyric clock and translation-hidden preview text;
- desktop lyric messages preserving duration while omitting hidden translations, without starting a desktop process.

Command:

`flutter test test/component/lyric_view_controls_test.dart test/component/lyric_source_view_test.dart test/play_service/desktop_lyric_service_test.dart`

Expected result: exit 1. Compilation failed because the new controller constructor/options and methods, `lyricSourcePreviewLine`, `lyricSourcePreviewText`, and `desktopLyricLineMessage` did not exist. The failures were therefore caused by the missing Task 5 behavior, not a runtime fixture or external device.

### GREEN — minimal implementation

The controller was given injected preference/save boundaries for deterministic tests while defaulting to `AppPreference.instance`; new changes call the existing preference setters, save with `unawaited`, and notify the controller only when a value actually changes. Source preview and desktop message helpers use the shared timing/presentation APIs.

The first GREEN run exposed one test-only static-type issue: `lyricSourcePreviewLine` correctly returns the common `LyricLine` type, while the test accessed `content` without narrowing it to `LrcLine`. The assertion was corrected with an explicit type check/cast; production behavior was unchanged.

Command:

`flutter test test/component/lyric_view_controls_test.dart test/component/lyric_source_view_test.dart test/play_service/desktop_lyric_service_test.dart`

Result: exit 0, 7 tests passed.

## Implementation summary

- `LyricViewController`
  - exposes `lyricOffsetMs` and the existing `showTranslation` preference;
  - increases/decreases by `lyricOffsetStepMs`, resets to zero, and relies on the shared clamp limit;
  - toggles translation with the existing preference setter;
  - persists changes asynchronously and notifies its UI listeners;
  - does not access audio files, lyric-source files, playback state, or desktop processes.
- `LyricViewControls`
  - adds a Chinese offset menu with decrease/current/increase/reset rows, signed millisecond display, and disabled boundary/no-op actions;
  - adds a Chinese translation show/hide button only when the current lyric future contains a translation;
  - retains the existing source, alignment, and font controls and Material Symbols/theme colors;
  - adds Chinese tooltips to the existing lyric-source button/loading state.
  - keeps the controls mounted while the offset menu overlay is open, matching the existing source-menu lifecycle.
- Source preview
  - selects the current preview line using `lyricClockPosition` and the live lyric offset;
  - formats LRC and word-timed lines through `presentLyricLine`, so the global translation preference is honored;
  - preserves existing local/online/per-track source selection and does not alter search-result behavior.
- Desktop lyrics
  - builds the existing `LyricLineChangedMessage` through `presentLyricLine`;
  - preserves line duration and message type, and sends `null` translation when hidden;
  - leaves the `desktop_lyric` subproject unchanged;
  - mechanically replaces six deprecated `Color.value` reads with equivalent `toARGB32()` calls so affected-file analysis is clean.
- Existing vertical lyric tiles and horizontal lyrics already use `presentLyricLine`; the final scan found no remaining direct translation splitting/rendering in the main lyric views or desktop message path.

## Verification

- Formatting:
  - `dart format` on all 6 affected production/test Dart files: exit 0.
- Required Task 5 plus new regression tests:
  - `flutter test test/lyric/lyric_presentation_test.dart test/app_preference_test.dart test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart test/component/lyric_view_controls_test.dart test/component/lyric_source_view_test.dart test/play_service/desktop_lyric_service_test.dart`
  - Result: exit 0, 26 tests passed.
- Offset/view integration regressions:
  - `flutter test test/lyric/lyric_timing_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart`
  - Result: exit 0, 12 tests passed, including preference re-emission and horizontal/vertical presentation.
- Full suite:
  - `flutter test`
  - Result: exit 0, 106 tests passed.
- Affected-file analysis:
  - `flutter analyze lib/page/now_playing_page/component/lyric_view_controls.dart lib/page/now_playing_page/component/lyric_source_view.dart lib/play_service/desktop_lyric_service.dart test/component/lyric_view_controls_test.dart test/component/lyric_source_view_test.dart test/play_service/desktop_lyric_service_test.dart`
  - Result: exit 0, no issues found.
- `git diff --check`: exit 0; no whitespace errors (Git only printed configured LF-to-CRLF conversion notices during diff inspection).

## Review fix — offset menu overlay lifecycle

- Independent review finding: the offset `MenuAnchor` initially omitted the source menu's `onOpen/onClose` handling. Moving the pointer from the lyric `MouseRegion` into the overlay could therefore set `isHovering` false, remove the controls/anchor, and make the menu disappear.
- RED command: `flutter test test/component/lyric_view_controls_test.dart --plain-name "keeps lyric controls mounted while the offset menu is open"`
  - Result: exit 1 with `Expected: true`, `Actual: <false>` after the menu was visibly open.
- Fix: the offset menu now sets `ALWAYS_SHOW_LYRIC_VIEW_CONTROLS` on open and clears it on close, exactly like the existing source menu. The isolated widget test extracts and mounts only the offset control, so no `PlayService`, audio device, or desktop process is initialized.
- GREEN command: the same targeted command exited 0 with 1 test passed.
- Final combined regression command (Task 5, timing, presentation, search, and view integration): exit 0, 39 tests passed.
- Final affected-file analysis: exit 0, no issues found.

## Concerns

- None. Tests use direct controllers and pure presentation/message helpers; they do not initialize real audio devices or start the desktop lyric executable.
