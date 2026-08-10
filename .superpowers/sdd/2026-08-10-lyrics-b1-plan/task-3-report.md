# Task 3 Report: lyric preferences, timing, and presentation

Baseline: `464936f feat: support multilingual lyric search`

## TDD evidence

### Red

Command:

```powershell
flutter test test/lyric/lyric_timing_test.dart test/lyric/lyric_presentation_test.dart test/app_preference_test.dart
```

Result: exit code `1`, as expected before implementation. The compiler reported the missing `lib/lyric/lyric_timing.dart` and `lib/lyric/lyric_presentation.dart` imports, plus missing `NowPlayingPagePreference` fields, listeners, and setters such as `lyricOffsetMs`, `showTranslation`, and `setLyricOffsetMs`.

The `lyricHasTranslation` positive-path test was also mutation-checked. With its implementation temporarily changed to `return false`, this command failed as expected:

```powershell
flutter test test/lyric/lyric_presentation_test.dart
```

Output included `Expected: true` and `Actual: <false>` for `detects translations without modifying lyric lines`. The real implementation was restored afterward.

### Green

Command:

```powershell
flutter test test/lyric/lyric_timing_test.dart test/lyric/lyric_presentation_test.dart test/app_preference_test.dart
```

Result: exit code `0`; final output: `00:02 +17: All tests passed!`

## Verification

Commands:

```powershell
dart format lib/app_preference.dart lib/lyric/lyric_timing.dart lib/lyric/lyric_presentation.dart test/app_preference_test.dart test/lyric/lyric_timing_test.dart test/lyric/lyric_presentation_test.dart
flutter test test/lyric/lyric_timing_test.dart test/lyric/lyric_presentation_test.dart test/app_preference_test.dart
git diff --check
```

Results: formatting completed successfully, the task test suite passed, and `git diff --check` exited `0` with no whitespace errors.

## Scope delivered

- Added lyric timing helpers with the fixed effective-clock, display-start, clamp, and zero-length-safe progress semantics.
- Added non-mutating LRC/word-timed lyric presentation conversion and lyric-level translation detection.
- Extended `NowPlayingPagePreference` as a `ChangeNotifier` while preserving four positional constructor arguments; added safe JSON compatibility, default values, and change-only notification setters.
- Did not modify lyric services, lyric views, desktop lyrics, or control menus.
