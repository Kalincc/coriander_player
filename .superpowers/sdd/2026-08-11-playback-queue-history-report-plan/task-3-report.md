# Task 3 implementation report

Status: DONE

## Scope delivered

- Added versioned `PlaybackHistoryEvent` JSON value objects.
- Added `PlaybackHistoryService` with single-session maximum-position tracking,
  the `min(30 seconds, duration * 0.5)` qualification threshold, a 30-second
  fallback for unknown duration, 12-month retention, persistent qualified
  events, and reverse-chronological `recent20`.
- Added pure local week/month/range reporting and song, original artist, and
  original album Top 10 aggregation.
- Added `PlayService.loadPlaybackHistory()` and a public loaded-service getter
  for the later playback lifecycle integration task.

## TDD evidence

RED command:

```text
flutter test test/library/playback_history_models_test.dart test/play_service/playback_history_service_test.dart test/library/listening_report_test.dart
```

Observed expected failure: all three newly referenced production files were
missing, so the test compiler reported missing imports and undefined
`PlaybackHistoryEvent`, `PlaybackHistoryService`, `ReportPeriod`, and
`buildListeningReport` symbols.

GREEN command:

```text
flutter test test/library/playback_history_models_test.dart test/play_service/playback_history_service_test.dart test/library/listening_report_test.dart
```

Result: 6 tests passed.

## Required checks

```text
dart format lib/library/playback_history_models.dart lib/library/listening_report.dart lib/play_service/playback_history_service.dart lib/play_service/play_service.dart test/library/playback_history_models_test.dart test/play_service/playback_history_service_test.dart test/library/listening_report_test.dart
git diff --check
```

Both completed successfully. Flutter regenerated unrelated Windows plugin
registrant files during test setup; those files were restored to `HEAD` and
are not part of this task.

## Limitations / follow-up boundary

This task exposes the history service but does not attach it to BASS playback
events. Task 4 owns lifecycle calls for load/start/pause/switch/completion/
close and the UI consumers.

## Fix round 1

Review found that a resumed playback session could treat the player's absolute
position as newly listened time. `startSession` now accepts an optional
`initialPosition`, and `recordPosition` records only the non-negative maximum
of `position - initialPosition`. A RED regression test demonstrated that the
new named parameter was missing; after implementation, a session resumed at
30 seconds and advanced to 31 seconds does not create a second qualified
event.

Verification reran the required three targeted test files: 7 tests passed.
