# Final fix report: Traditional/Simplified artist merge

Date: 2026-08-04
Branch: `agent/merge-traditional-simplified-artists`
Reviewed starting range: `3486e28..2b3afda`
Fix commit: `d6636f7a1bdcd42580c7475a303508fe7794f2ef`

## Outcome

DONE. The two Important review defects and the low-cost normalizer test gap are fixed. The branch remains local; it was not pushed and no pull request was created.

## Defect 1: exact canonical lookup preserves whitespace

Root cause: `albumsForArtist` normalized `artistName.trim()` before indexing the canonical artist map. Canonical keys intentionally preserve whitespace, so a selected key such as ` 張學友 ` was changed to `张学友`, missed the stored ` 张学友 ` entry, and incorrectly returned all albums.

Fix:

- Changed the canonical lookup to `artists[normalizeArtistName(artistName)]`.
- Left the deliberate `query.trim()` behavior in `filterArtistNames` unchanged.
- Added a regression with the canonical key ` 张学友 ` and raw selection ` 張學友 `.

TDD evidence:

- RED: `flutter test --no-pub test/page/album_artist_filter_test.dart test/library/artist_name_normalizer_test.dart` exited 1 at `+6 -1`; the whitespace-bearing selection returned the all-albums entry instead of the artist's album.
- GREEN: the same command exited 0 with 8 tests passed after removing only the lookup-path trim.

## Defect 2: per-audio canonical artist collisions

Root cause: collection and UI loops iterated `Audio.splitedArtists` directly. For one audio tagged `張學友/张学友`, both raw values normalize to `张学友`; collection construction appended the same `Audio` twice to `Artist.works`, and the AudioTile, audio-detail, and now-playing paths each rendered/resolved the same canonical artist twice.

Fix:

- Added `_canonicalArtistNames(Audio)`, which normalizes split names and removes canonical duplicates with an insertion-ordered set.
- Kept alias recording over every raw split value so both `張學友` and `张学友` still resolve.
- Used the deduplicated canonical sequence before appending `Artist.works` and before linking `Album.artistsMap`.
- Added `AudioLibrary.artistsForAudio(Audio)` as the single ordered, linkable canonical-artist boundary.
- Routed AudioTile, audio detail, and now-playing artist menus through `artistsForAudio`.
- Preserved raw `Audio.artist`, raw `Audio.splitedArtists`, separator behavior, canonical insertion order, album behavior, and no-category behavior.

TDD evidence:

- RED (collection): `flutter test --no-pub test/library/audio_library_artist_merge_test.dart` exited 1 at `+2 -1`; `Artist.works` contained the same audio twice.
- GREEN (collection): the command exited 0 with 4 tests passed after canonical deduplication.
- RED (linkable boundary): the collection test initially failed to compile because `artistsForAudio` did not exist.
- GREEN (linkable boundary): the collection test passed after the minimal boundary was added.
- RED (UI): `flutter test --no-pub test/page/audio_artist_rendering_test.dart` exited 1 with 2 failures; AudioTile exposed two canonical menu items and audio detail rendered two `ArtistTile` widgets.
- GREEN (UI): the same command exited 0 with 2 tests passed after all three UI paths adopted the boundary. The now-playing path consumes the same tested list; a separate service-heavy now-playing harness was not added.

The collision regression also explicitly asserts:

- `Audio.artist == '張學友/张学友'`;
- `Audio.splitedArtists == ['張學友', '张学友']` in the original order;
- one canonical `artistCollection` entry;
- one `Artist.works` relationship;
- one album-to-artist relationship;
- one linkable canonical artist result.

## Minor normalizer coverage

Added an explicit unmapped-character assertion: `normalizeArtistName('🎵') == '🎵'`. This required no production change.

## Fresh verification

### Focused feature command

Command:

```powershell
flutter test --no-pub test/library/artist_name_normalizer_test.dart test/library/audio_library_artist_merge_test.dart test/page/album_artist_filter_test.dart test/page/search_result_page_test.dart test/component/lyric_search_result_tile_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
```

Result: exit 0, `+20`, all tests passed. This is the original 17-test command with the three new regressions embedded in existing test files.

Additional UI command:

```powershell
flutter test --no-pub test/page/audio_artist_rendering_test.dart
```

Result: exit 0, `+2`, all tests passed.

Combined scoped result: 22/22 tests passed, 0 failures.

### Formatting and analysis

- `dart format --output=none --set-exit-if-changed` over the 12 feature/test files: exit 0, 12 files checked, 0 changed.
- Feature-boundary `flutter analyze --no-fatal-infos` over the same 12 files: exit 0. It reported four existing info-level diagnostics only:
  - `NOW_PLAYING_VIEW_MODE` naming;
  - two deprecated `ShowValueIndicator.always` uses;
  - `SEARCH_BAR_KEY` naming.

### Diff and metadata audit

- `git diff --check`: exit 0 before commit.
- `git diff --check 3486e28..d6636f7`: exit 0.
- Production diff search found no added assignment to `Audio.artist` or `Audio.splitedArtists`.
- The explicit collision regression confirms both raw fields remain unchanged.
- Final feature range `3486e28..d6636f7`: 15 files changed, 414 insertions, 70 deletions.
- The Windows workflow is unchanged and still performs checkout, Flutter setup, `flutter pub get`, `flutter build windows`, BASS placement, and artifact upload.

## Remaining concerns / intentionally deferred items

- Remote Windows packaging remains pending an authorized push/workflow dispatch, as already recorded in the SDD ledger.
- Full-project analysis remains outside the approved local gate because of unrelated baseline sources/configuration; feature-boundary analysis passes its configured gate.
- The public `rebuildCollections()` test hook remains unchanged, per final-review scope.
- No unrelated refactor, dependency change, metadata rewrite, push, or PR creation was performed in this fix wave.
