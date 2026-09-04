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

## Review follow-up

Added regression coverage for version-preserving candidate keys, mixed version-token conflicts, normalized/pinyin partial overlap, and duration boundaries. The scorer now includes sorted version tokens in `musicCandidateKey`, treats version sets as a match only when equal (any extra or missing token is a conflict), and performs token overlap on normalized fields.

The pinned `music_api_dart` fixture data shows Kugou `duration` and QQ `interval` in seconds, while NetEase `duration` is millisecond-valued (for example `213200`). NetEase integration now explicitly converts milliseconds to rounded seconds before scoring; this is documented inline in `lib/music_matcher.dart`.

Review-fix TDD evidence:

- Red: the added tests failed on the pre-fix implementation for key separation, mixed-version conflict handling, and the initially over-specific duration expectations.
- Green: `flutter test test/lyric/music_match_normalizer_test.dart` passed all 6 tests after the fixes.
- Fix commit: `d8b7c76d3f55f63f214fc058aac753e9d9580fb4` — `fix: preserve music version matching distinctions`.
- Final focused verification: 14 tests passed across the existing lyric normalizer, new music normalizer, and matcher tests; `flutter analyze lib/lyric/music_match_normalizer.dart lib/music_matcher.dart` reported `No issues found!`.

## Review follow-up round 2

Added a strict artist-only comparison against an unrelated artist, so the pinyin partial-match assertion cannot pass from title or album points. Token overlap now evaluates every normalized, simplified, spaced-pinyin, and compact-pinyin form pair and chooses the strongest Jaccard overlap deterministically.

Red evidence: the strengthened artist test failed before the change because the pinyin candidate and unrelated candidate scored equally (`0.7`). Green evidence: `flutter test test/lyric/music_match_normalizer_test.dart test/music_matcher_test.dart` passed all 7 tests, and analyzer reported `No issues found!`.

Fix commit: `c394929071f9929635887983cf5f07126c8c5b11` — `fix: score pinyin partial artist matches`.
