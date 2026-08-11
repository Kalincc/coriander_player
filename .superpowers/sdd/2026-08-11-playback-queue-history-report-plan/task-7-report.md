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
