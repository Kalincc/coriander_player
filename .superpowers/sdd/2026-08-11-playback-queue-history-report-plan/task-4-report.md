# Task 4 report — playback lifecycle, queue editor, and liked-song UI

## Scope delivered

- `PlaybackService` now attaches `PlaybackHistoryService`, starts sessions only
  after successful source load/start, records valid position updates, finalizes
  on pause/complete/close, and resumes from the saved absolute position without
  counting prior listening time again.
- `CurrentPlaylistView` uses `PlaybackQueueService` as its only editable queue:
  drag reorder, remove, clear, current-row highlight, and empty state.
- Added `NowPlayingFavoriteButton`; it is present in mini and large/small
  now-playing controls, toggles the protected liked playlist, and does not
  request playback. System playlists hide rename/delete controls.

## TDD evidence

- RED: before implementation,
  `flutter test test/component/now_playing_favorite_button_test.dart test/component/current_playlist_view_test.dart`
  failed because `NowPlayingFavoriteButton` did not exist and
  `CurrentPlaylistView` had no queue-service injection interface.
- GREEN (component scope): the same two test files pass, 5 tests total.
- GREEN (Task 4 regression scope):
  `flutter test --no-pub test/component/now_playing_favorite_button_test.dart test/component/current_playlist_view_test.dart test/play_service/playback_queue_service_test.dart test/play_service/playback_history_service_test.dart -r expanded`
  passed, 13 tests total.

## Test hang investigation

The first queue-widget test used `LocalJsonStore` disk writes inside a
`testWidgets` fake-async zone. `queue.setQueue` then waited on real file I/O,
so the test never completed. Existing non-widget queue tests passed, and a
minimal widget test without real storage passed. The component test now uses a
small in-memory `LocalJsonStore` fake; production storage is unchanged.

## Checks

- `dart format` on all affected Dart files: pass.
- `dart analyze` of the new/changed lifecycle and widget files: no errors;
  only three pre-existing `_nextAudio_*` naming infos in `PlaybackService`.
- `git diff --check`: pass.

## Deferred

- Direct BASS-backed playback lifecycle integration cannot run in a headless
  widget test. The existing history-service tests cover qualification and
  resumed-position delta behavior; manual desktop playback remains appropriate
  for final user-facing audio verification.

## Fix round 1

- Startup now calls `PlayService.initializePlaybackData` after library loading
  in both the normal updating route and first-library-build route. The helper
  loads/attaches the queue before history; its closure-based initializer has a
  headless test that verifies this startup wiring order.
- Queue removal and clear now go through `PlaybackService`. When the current
  item is affected it pauses BASS, snapshots/finalizes the history session,
  and only then clears the queue state; non-current removal leaves playback
  alone. Component tests cover current-path removal and clear behavior.
- History finalization is now nonblocking from playback transitions. History
  events are finalized in memory synchronously while JSON writes are serialized
  in the background. A delayed-store test verifies the lifecycle finalizer does
  not wait for persistence and existing double-finalization coverage remains.
- Seeking resets the history position baseline, retaining only actual listened
  deltas. A 0-to-two-minute seek-and-end regression test confirms no qualified
  event is created.

### Fix round 1 RED/GREEN

- RED: the seek regression and startup initializer tests initially failed to
  compile because `recordSeek` and `PlaybackDataInitializer` did not exist.
- GREEN: `flutter test --no-pub test/component/now_playing_favorite_button_test.dart test/component/current_playlist_view_test.dart test/play_service/playback_queue_service_test.dart test/play_service/playback_history_service_test.dart test/play_service/play_service_initialization_test.dart -r expanded` passed, 17 tests.
- `dart format`, targeted `dart analyze` (no errors; only three existing
  `_nextAudio_*` naming infos), and `git diff --check` passed.
