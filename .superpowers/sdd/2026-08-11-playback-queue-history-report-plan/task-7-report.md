# Task 7 report — documentation, migration coverage, and final verification

## Changes

- Documented the persistent local data directory, upgrade/reinstall behavior,
  backup/restoration procedure, protected `我喜欢` playlist, queue restoration,
  history/report rules, and legacy-index full rebuild path in `README.md`.
- Made `PlaybackQueueService.load` treat corrupt optional recovery data as an
  empty inert queue, so startup remains usable and never auto-plays.
- Added focused migration coverage for corrupt `playback_queue.json.tmp` and
  `playback_queue.json.bak` with a missing primary queue file.

## TDD evidence

- RED: `flutter test test/play_service/playback_queue_service_test.dart`
  failed in `starts with an empty inert queue when optional recovery files
  corrupt` with `FormatException: Unexpected character` from
  `LocalJsonStore._decode`.
- GREEN: after the minimal queue-load recovery guard, the same command passed
  `5/5` tests.

## Migration coverage reviewed

- Legacy `playlists.json` without `isSystem`: covered by existing playlist
  migration test; old songs are retained and the protected playlist is added.
- Repeated playlist startup: covered by the existing duplicate-liked migration
  test, which calls `readPlaylists` twice.
- Missing queue/history files: their load paths initialize empty usable state;
  queue restoration never starts playback.
- Corrupt `.tmp`/`.bak`: the new queue regression test verifies startup stays
  usable. Playlist and history loaders already contain their own recovery
  boundaries.

## Verification

- Required targeted integration suite was started once, but produced no Flutter
  framework output for about 60 seconds and was safely terminated as required.
- `dart format --output=none --set-exit-if-changed lib test` reported one
  transient `lib/src/rust/api/tag_reader.dart` formatting change, while the
  subsequent Git diff contained no change to that file. The changed Task 7
  Dart files were then checked directly: `Formatted 2 files (0 changed)`.
- `flutter analyze lib test` completed with 66 existing `info` diagnostics and
  no warning/error diagnostics; it exited 1 because those infos are treated as
  issues by this project configuration.
- `git diff --check` passed.
- Static side-effect scan found only the existing local JSON/index/lyric file
  access in `lib/library`; no new network or audio/tag write path was added.
- The required single final `flutter test` attempt likewise produced no output
  for about 60 seconds and was safely terminated. It was not retried.
- Cargo/Rust verification was not attempted and no toolchain was installed,
  per the task brief.

## Final review fix round 1

- Full rebuild scanning now propagates root/subdirectory `read_dir`, directory
  entry, file-type, recursive, metadata, and modified-time failures. The
  top-level rebuild uses `?`, so a failed scan cannot write a partial index;
  the existing coordinator already stops reload/reconcile after a scan error.
  A static Rust regression test covers a missing/unreadable full-rebuild root.
- `cargo --version` confirmed Cargo is not installed on this machine. No Rust
  toolchain was installed; the new Rust test was added but could not run.
- The listening report now renders a non-playable “最近播放” section using the
  service's newest-first `recent20` list, with title/path fallback, listened
  duration, timestamp, 20-item cap, and empty state. README now calls this
  out explicitly.
- Queue attachment snapshots the restored ordered queue before shuffle is
  used; enabling shuffle refreshes that snapshot, and disabling shuffle falls
  back to the current queue rather than clearing it.
- Regular playlists now reject the protected `我喜欢` name at construction,
  repository creation, and rename boundaries. Legacy JSON is still parsed so
  startup migration can merge old duplicate names. The UI shows a failure
  message for a rejected create/rename.
- AudioTile's right-click menu now includes “添加到播放队尾”, routed through
  `PlaybackService.appendToQueue` and the de-duplicating persisted queue API.
- Corrected two pre-existing listening-report expectations: UTC end uses the
  microsecond parameter, and Top 10 retains the missing-metadata path fallback.

### Fix-round verification

- RED/GREEN: reserved-name playlist test failed before the constructor/repository
  guard and then passed; `flutter test test/library/playlist_test.dart` passed
  6/6. The append command test failed to compile before its command helper and
  then `flutter test test/play_service/playback_queue_service_test.dart` passed
  6/6. The new report-page test was written before the UI change, but its Flutter
  runner produced no framework output for about 60 seconds in both attempts and
  was safely stopped rather than retried further.
- `flutter test test/library/listening_report_test.dart` passed 3/3.
- `flutter analyze lib test` reports the existing 66 info diagnostics and no
  warning/error diagnostics. Changed Dart files were formatted.
- The one permitted final `flutter test` attempt produced no framework output
  for about 60 seconds and was safely terminated; it was not retried.
