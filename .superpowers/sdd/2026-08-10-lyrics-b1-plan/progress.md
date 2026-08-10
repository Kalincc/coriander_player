# SDD ledger — plan: docs/superpowers/plans/2026-08-10-lyrics-b1-plan.md

Baseline: `19d33f5` (`codex/lyrics-b1`), focused baseline tests passed (52 tests, 0 failures).

Task 1: complete (commits 19d33f5..1f142f0, review clean)
Task 2: minor (deferred): LyricSearchLine.searchForms exposes a mutable List; final review to triage.
Task 2: complete (commits 1f142f0..464936f, review clean; 1 minor deferred)
Task 3: complete (commits 464936f..89a3648, review clean)
Task 4: fix round 1/5 (0 addressed, 1 open; position-stream rollback can retain old _nextLyricLine; commits 89a3648..2267f82)
Task 4: fix round 1/5 (1 addressed, 0 open; rollback recomputes absolute lyric index; commits 2267f82..ed410fb)
Task 4: complete (commits 89a3648..ed410fb, review clean)
Task 5: fix round 1/5 (0 addressed, 2 open; menu lifecycle/circular dependency and unrelated Color.value migration; commits ed410fb..37c0e36)
Task 5: fix round 1/5 (2 addressed, 0 open; controller-owned menu state and unrelated color migration removed; commits 37c0e36..d3c5acc)
Task 5: minor (deferred): serialize/coalesce rapid preference saves; add direct widget coverage for hidden translation/boundary/Sync desktop output.
Task 5: complete (commits ed410fb..d3c5acc, review clean; 2 minors deferred)
Task 6: complete (commits d3c5acc..b92fdc3; focused regression 81/81 and affected tests 33/33 passed; baseline-only analyzer info)
Final review: complete (range 19d33f5..09be2aa; 0 Critical, 0 Important, 3 deferred Minor; Ready to merge: Yes)
Final verification: `flutter test` passed 109/109; worktree clean.
