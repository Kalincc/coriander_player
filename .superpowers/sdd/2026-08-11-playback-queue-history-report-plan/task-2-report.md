# Task 2 report — persistent playback queue

## Scope

- Added the versioned, path-only `PlaybackQueueService` backed by
  `LocalJsonStore` (`playback_queue.json`).
- Added PlayService initialization/loading entry point and playback-service
  synchronization while retaining the existing `ValueNotifier<List<Audio>>`
  compatibility surface.
- Restored queue metadata does not call the audio engine. A later user-initiated
  `start()` loads the restored current source and seeks to its saved position.

## TDD evidence

### RED

Command:

```text
flutter test test/play_service/playback_queue_service_test.dart
```

Result: failed as expected because
`lib/play_service/playback_queue_service.dart` and
`PlaybackQueueService` did not exist.

### GREEN

Commands:

```text
flutter test test/play_service/playback_queue_service_test.dart
flutter test test/play_service/playback_queue_service_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
dart format lib/play_service/playback_queue_service.dart lib/play_service/playback_service.dart lib/play_service/play_service.dart test/play_service/playback_queue_service_test.dart
git diff --check
```

Results: queue tests passed (3 tests); queue plus lyric regression passed
(8 tests); formatting and whitespace checks completed cleanly. Flutter's
dependency resolution printed routine newer-package notices only.

## Files changed

- `lib/play_service/playback_queue_service.dart`
- `lib/play_service/play_service.dart`
- `lib/play_service/playback_service.dart`
- `test/play_service/playback_queue_service_test.dart`

## Notes for the next task

- `PlayService.loadPlaybackQueue(Iterable<Audio>)` is the startup hook. Task 5's
  library-update coordinator should call it after `AudioLibrary` has loaded so
  queue paths are reconciled with the actual library; it does not start audio.
- Queue persistence failures are logged and do not prevent the existing
  playback UI from continuing to operate.

## Fix round 1 — shuffle backup after insert-next

Review identified that the queue-backed `PlaybackService.addToNext` path
updated only `PlaybackQueueService`; `_playlistBackup` remained stale and
could remove the newly inserted song when shuffle was later disabled.

- RED: the new shuffle-restoration regression failed because the playback
  queue snapshot handoff did not exist.
- GREEN: `addToNext` now snapshots the queue immediately after its synchronous
  in-memory `insertNext` mutation, before the asynchronous persistence work
  finishes. The snapshot remains the source used when shuffle is disabled.
- Verification: `flutter test test/play_service/playback_queue_service_test.dart`
  passed 4 tests; the queue plus lyric regression command passed 9 tests;
  formatting and `git diff --check` passed.
