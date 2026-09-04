# Task 2 report: query normalization, version recognition, and deterministic scoring

## Files

- `lib/lyric/music_match_normalizer.dart`: added `MusicMatchScore`, bounded query generation, normalized/pinyin-aware comparison, version-token adjustment, duration scoring, and U+001F candidate keys.
- `lib/music_matcher.dart`: replaced the legacy character-prefix score with `scoreMusicCandidate`; online search now starts from the normalized title+artist query.
- `test/lyric/music_match_normalizer_test.dart`: added the required bounded-query and version-conflict tests.
- `test/music_matcher_test.dart`: verifies `SongSearchResult` uses the normalized scorer without contacting online services.

## TDD evidence

Red command:

```powershell
flutter test test/lyric/music_match_normalizer_test.dart
```

Result: failed during test loading because `lib/lyric/music_match_normalizer.dart` did not exist; the expected functions were consequently unresolved (`musicSearchQueriesFor`, `scoreMusicCandidate`).

Green command:

```powershell
flutter test test/library/lyric_search_normalizer_test.dart test/lyric/music_match_normalizer_test.dart test/music_matcher_test.dart
```

Result: `All tests passed!` (10 tests).

Additional verification:

```powershell
flutter analyze lib/lyric/music_match_normalizer.dart lib/music_matcher.dart
```

Result: `No issues found!`.

## Commit

- `e59c63578315a176bf40ec8cd3bdd83a9bc42ee3` — `feat: add normalized music lyric matching`

## Concerns

- The matcher currently selects the highest-priority normalized query as its single service query; broader multi-query aggregation/deduplication remains for the later result-model work.
- Existing Task 1 generated Windows plugin-registration modifications were left untouched and uncommitted.
