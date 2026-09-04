# Task 1 implementation report

## Files changed

- `rust/src/api/tag_reader.rs`: added `select_lyric_text`, Lofty `Lyrics` plus unknown raw-tag alias collection, and the alias-selection unit test.
- `lib/library/lyric_search_index.dart`: fingerprints the audio file's actual mtime in seconds, with fallback to `Audio.modified` when stat fails.
- `test/library/lyric_search_index_test.dart`: verifies a stale `Audio.modified` is ignored in favor of the file mtime.

## TDD evidence

- Rust RED: added `lyric_alias_prefers_the_first_timed_value` before implementation. The requested `cargo test --manifest-path rust/Cargo.toml tag_reader -- --nocapture` could not execute because Cargo is not installed (`cargo: The term 'cargo' is not recognized...`). Therefore no Rust compile/test result is claimed.
- Dart RED: focused Flutter test failed as intended before implementation: expected `3`, actual `42` at `test/library/lyric_search_index_test.dart:140`.
- Dart GREEN: `flutter test test/library/lyric_search_index_test.dart` passed: `00:00 +22: All tests passed!`.
- Static check: `flutter analyze lib/library/lyric_search_index.dart test/library/lyric_search_index_test.dart` passed with `No issues found!`.

## Commit

- Implementation commit: `1478d6ab7d79f0fc71150aa8aaa49b5b87f60a33`.
- This report update is committed separately so the implementation hash remains stable.

## Concerns

- Rust tests and compilation remain unverified because this host has no Cargo/rustfmt toolchain. The implementation targets the locked Lofty 0.21.1 API (`Tag::items`, `TagItem::key/value`, `ItemKey::Unknown`).
- Existing unrelated generated Windows Flutter files were already modified and were not included.

## Reviewer follow-up fixes

- Added `lyric_alias_rejects_colons_outside_a_timestamp_bracket`, which proves `[description] notes: value]` is rejected and selection falls through to the next valid alias.
- Changed raw unknown-key collection to own the key with `to_string()`, avoiding a borrowed `&String` in the `(String, String)` candidate vector.
- LRC detection now finds the first closing `]` and requires `:` within the enclosed substring.
- Follow-up checks: `flutter test test/library/lyric_search_index_test.dart` passed (`+22`); `flutter analyze lib/library/lyric_search_index.dart test/library/lyric_search_index_test.dart` passed (`No issues found!`). Cargo remains unavailable (`cargo: The term 'cargo' is not recognized...`), so Rust compilation is still unverified.
