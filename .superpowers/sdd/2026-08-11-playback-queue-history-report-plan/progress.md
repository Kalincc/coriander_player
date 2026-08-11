# SDD ledger — plan: docs/superpowers/plans/2026-08-11-playback-queue-history-report-plan.md

Baseline: `263fd33` (`codex/a-playback-history-report`), `flutter test` passed 109 tests; generated Windows plugin files restored as unchanged.
Plan clarification: `5e656cd` corrected the effective-play threshold to `min(30 seconds, duration * 0.5)` for “30 seconds or 50%, whichever comes first”.
Task 1: fix round 1/5 (0 addressed, 1 Critical open; LocalJsonStore.read must recover `.bak` before playlist migration writes).
Task 1: fix round 2/5 (0 addressed, 1 Critical open; backup is parsed but not restored as the primary file before a later write).
Task 1: fix round 2/5 resolved (`7f1d92d`; backup is safely restored as primary while retaining `.bak`, including simulated later-write failure).
Task 1: review READY (`task-1-rereview2.md`; 10/10 scoped tests, no static issues). Deferred Minor: restrict arbitrary `isSystem=true` to only the protected “我喜欢” playlist.
Task 1: complete (`72056e7`, `1024469`, `7f1d92d`; protected local JSON store and playlist migration delivered).
Task 2: implementation `fc21ea0` (persistent path-only queue, reconciliation, current position, compatibility sync; scoped 8-test regression passed).
Task 2: review found Important: `addToNext` did not refresh `_playlistBackup`, so shuffle exit could drop the new item.
Task 2: fix round 1 `74c8c62`; review READY (`task-2-rereview.md`, queue 4/4 and static checks clean).
Task 2: complete (`fc21ea0`, `74c8c62`; deferred startup restore wiring belongs to Task 5).
