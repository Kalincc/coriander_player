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

## Final reviewer addendum

- Added regression coverage for metadata timestamps (`[ti:Song]`), leading non-timestamp brackets followed by a valid timestamp, and malformed TTML falling through to a later valid alias.
- LRC recognition now scans every line and bracket pair, requiring numeric minutes and finite seconds in the range `[0, 60)`; metadata such as `[ti:Song]` is rejected.
- TTML recognition now requires a `<tt>` root delimiter, `<body`, and `</tt>` before selecting the candidate.
- Final checks: `flutter test test/library/lyric_search_index_test.dart` passed (`00:00 +22: All tests passed!`); Flutter analyze passed (`No issues found!`). `cargo test --manifest-path rust/Cargo.toml tag_reader -- --nocapture` remains blocked because Cargo is not installed.

## Second reviewer addendum

- Added regressions for BOM/XML declaration plus namespaced `<tt>` documents, and for empty `<body>` falling through to a valid alias.
- TTML preselection now skips BOM/XML declarations, accepts `tt` or namespaced `*:tt` roots and namespaced body tags, requires matching closing tags and non-empty body content, and therefore does not mask later aliases or sidecar fallback.
- Verification: `flutter test test/library/lyric_search_index_test.dart` passed (`00:00 +22: All tests passed!`). Cargo remains unavailable, so Rust tests/compile are unverified.

## Third reviewer addendum

- Added regressions for whitespace-only TTML, div-only body, and paragraphs missing `end`/`dur`; corrected the positive namespaced fixture with a valid end time.
- TTML preselection now requires a namespace-independent non-empty `<p>` with numeric `begin`, a valid positive `end` or `dur`, a matching closing tag, and visible text. Invalid candidates continue to later aliases/fallback.
- Verification: `flutter test test/library/lyric_search_index_test.dart` passed (`00:00 +22: All tests passed!`). Cargo is unavailable (`cargo: The term 'cargo' is not recognized...`), so Rust tests/compile remain unverified.

## Fourth reviewer addendum

- Added TDD regression coverage for Dart-compatible decimal, `mm:ss`, and `HH:mm:ss` timing forms, quoted attributes with spacing, and empty `<span>` text falling through.
- Added timestamp parsing with non-negative finite values and proper 1/2/3-part range validation; attribute extraction accepts single/double quotes and whitespace around `=`.
- Visible-text validation now ignores XML tags and comments, requiring actual text outside tags in a timed `<p>` with valid `begin` plus positive `end` or `dur`.
- Verification: `flutter test test/library/lyric_search_index_test.dart` passed (`00:00 +22: All tests passed!`). Cargo remains unavailable, so Rust tests/compile are unverified.
