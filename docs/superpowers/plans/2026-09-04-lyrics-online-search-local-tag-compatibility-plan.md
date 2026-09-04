
# Lyrics Online Search and Local Tag Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox ( - [ ] ) syntax for tracking.

**Goal:** 让播放器可靠读取 LYRIC/LYRICS，并通过多来源、可解释的自动匹配和候选回退提高在线歌词命中率。

**Architecture:** 保留现有 music_matcher.dart 的公开顶层函数作为兼容 facade，把来源结果、适配器接口和在线歌词 payload 拆成小型模型；搜索编排层负责查询生成、供应商隔离、去重和评分，歌词获取层负责缓存、解析和失败回退。Rust 只负责从 Lofty 标签中按别名选择候选文本，Dart 继续使用现有 TTML/LRC/KRC/QRC 解析器。

**Tech Stack:** Flutter/Dart 3.1.4+、Rust 2021、Lofty 0.21.1、现有 music_api Git 锁定版本 c6f3e0abd9c6295b3678ce10d30bc09debda9abe、Flutter test、Cargo test。

## Global Constraints

- 本地读取同时兼容 LYRIC、LYRICS、现有嵌入式歌词和同名 .lrc，不修改音频文件。
- 已有歌词索引格式保持 v2；只因实际音频或 sidecar 修改时间变化而增量刷新。
- 在线来源只使用现有 QQ、酷狗、网易云适配；单个来源超时或格式错误不能阻断其他来源。
- 每个来源最多保留 10 条候选；来源查询最多使用“标题+艺术家”“标题”“标题+专辑”三种唯一查询，并按需要停止。
- 单个来源请求超时固定为 8 秒；自动获取歌词最多按排序尝试 8 条候选。
- 标题精确匹配权重最高；评分必须确定、可解释，并包含版本冲突惩罚和时长接近加分。
- 自动采用候选的最低分数固定为 0.62；低于该值的候选仍保留在候选窗口，但不自动替换为当前歌词。
- 自动匹配只影响当前播放；只有用户在候选窗口点击后才写入现有 LYRIC_SOURCES，应用退出时仍由现有流程保存。
- 在线缓存只写应用数据目录，使用版本化 JSON 和临时文件原子替换，最多保留 200 条最近成功结果。
- 缓存条目的有效期固定为 30 天；超过有效期或音频指纹不一致时视为未命中。
- 不新增账号、聚合服务、音频标签写入、歌词时间轴编辑或独占播放模式改动。
- 所有功能实现遵循先写失败测试、确认失败、写最小实现、确认通过、再提交的 TDD 顺序。

---

## 执行前置

开始 Task 1 前在当前仓库运行：

~~~
powershell
git status --short --branch
git log -1 --oneline
~~~

当前 main 应保持干净；执行功能开发时使用 using-git-worktrees 创建独立工作树和 codex/lyrics-online-search 分支，不触碰已有 .worktrees/a-playback-history-report。设计文档提交 8a774f9 必须作为基线保留。

## 文件地图

### 新建文件

- lib/lyric/online_lyric_models.dart：ResultSource、SongSearchResult、OnlineLyricPayload 和 OnlineLyricProvider 的稳定接口。
- lib/lyric/music_match_normalizer.dart：查询生成、标题/艺术家/专辑/版本标准化、候选评分和去重键的纯函数。
- lib/lyric/online_lyric_cache.dart：版本化在线歌词缓存、指纹校验、200 条上限和原子写入。
- test/lyric/music_match_normalizer_test.dart：标准化和评分测试。
- test/lyric/online_lyric_cache_test.dart：缓存读写、过期、损坏和淘汰测试。
- test/music_matcher_test.dart：来源隔离、候选去重和正文回退测试。

### 修改文件

- rust/src/api/tag_reader.rs：Lofty 原始标签别名读取和时间戳候选选择。
- lib/library/lyric_search_index.dart：使用实际音频文件修改时间作为 audioModified。
- test/library/lyric_search_index_test.dart：验证实际 mtime 变化触发增量读取。
- lib/music_matcher.dart：保留公开 facade，接入适配器、评分、缓存和候选正文回退。
- lib/play_service/lyric_service.dart：指定来源获取歌词时传入当前音频，使用缓存并保留手动来源语义。
- lib/page/now_playing_page/component/lyric_source_view.dart：显示来源/匹配信息，保留多候选预览和切换。
- test/component/lyric_source_view_test.dart：补充候选摘要和失败候选不阻塞的纯逻辑测试。
- README.md：更新本地标签兼容说明和在线匹配行为。

---

### Task 1: 本地 LYRIC 标签兼容与 mtime 指纹

**Files:**

- Modify: rust/src/api/tag_reader.rs:522-570 and its cfg(test) module
- Modify: lib/library/lyric_search_index.dart:19-31
- Test: test/library/lyric_search_index_test.dart

**Interfaces:**

- Produces the internal Rust helper select_lyric_text(candidates: impl IntoIterator<Item = (String, String)>) -> Option<String>.
- Keeps the generated FFI signature get_lyric_from_path(path: String) -> Option<String> unchanged.
- Keeps Dart readLocalLyricFingerprint(Audio) -> Future<LyricFileFingerprint> unchanged.

- [ ] **Step 1: Write the failing Rust alias-selection test**

Add this test shape to rust/src/api/tag_reader.rs:

~~~
rust
#[test]
fn lyric_alias_prefers_the_first_timed_value() {
    let candidates = vec![
        ("Lyrics".to_string(), "plain description".to_string()),
        ("LYRIC".to_string(), "[00:01.00]valid lyric".to_string()),
    ];

    assert_eq!(
        select_lyric_text(candidates),
        Some("[00:01.00]valid lyric".to_string())
    );
}
~~~

- [ ] **Step 2: Run the Rust test and verify it fails**

Run:

~~~
powershell
cargo test --manifest-path rust/Cargo.toml tag_reader -- --nocapture
~~~

Expected: FAIL because select_lyric_text does not exist.

- [ ] **Step 3: Implement the minimal Lofty alias path**

Implement select_lyric_text so it normalizes the supplied key name with Unicode lowercase, accepts only lyrics and lyric, and returns the first non-empty candidate whose trimmed text either starts with < (TTML) or contains a bracketed time marker with : and ]. In _get_lyric_from_lofty:

1. Read ItemKey::Lyrics and put it first in the candidate vector.
2. Enumerate the raw tag items supported by Lofty 0.21.1 and append custom LYRICS/LYRIC values with their original key names.
3. Convert each ItemValue text to String before calling the helper.
4. Return None when no candidate looks like TTML/LRC, allowing the existing .lrc fallback to run.

Use the actual Lofty 0.21.1 TagItem key/value accessors from the locked dependency; do not upgrade Lofty. Do not change the FFI generated file or the same-name .lrc decoding branch.

- [ ] **Step 4: Run the Rust test and verify it passes**

Run the same cargo test command. Expected: the alias test and the existing empty-root test pass.

- [ ] **Step 5: Write the failing Dart mtime test**

Extend the existing fingerprint test so Audio.modified is deliberately stale while the file mtime is known:

~~~
dart
await audioFile.setLastModified(
  DateTime.fromMillisecondsSinceEpoch(3_000),
);
final audio = makeAudio(audioFile.path, 42);

final fingerprint = await readLocalLyricFingerprint(audio);
expect(fingerprint.audioModified, 3);
~~~

- [ ] **Step 6: Run the Dart test and verify it fails**

Run:

~~~
powershell
flutter test test/library/lyric_search_index_test.dart
~~~

Expected: FAIL because the implementation still uses audio.modified (42).

- [ ] **Step 7: Implement actual file mtime with safe fallback**

In readLocalLyricFingerprint, use File(audio.path).lastModified() and store millisecondsSinceEpoch divided by 1000; if the file cannot be stat-ed, fall back to audio.modified and let the existing per-song error isolation handle lyric read failures. Preserve the sidecar path and sidecar mtime behavior.

- [ ] **Step 8: Run the focused tests and commit**

Run:

~~~
powershell
flutter test test/library/lyric_search_index_test.dart
cargo test --manifest-path rust/Cargo.toml tag_reader -- --nocapture
~~~

Expected: all focused tests pass. Commit:

~~~
powershell
git add rust/src/api/tag_reader.rs lib/library/lyric_search_index.dart test/library/lyric_search_index_test.dart
git commit -m "feat: read lyric tag aliases and refresh file fingerprints"
~~~

---

### Task 2: 查询标准化、版本识别和确定性评分

**Files:**

- Create: lib/lyric/music_match_normalizer.dart
- Create: test/lyric/music_match_normalizer_test.dart
- Modify: lib/music_matcher.dart
- Test: test/music_matcher_test.dart

**Interfaces:**

~~~
dart
class MusicMatchScore {
  final double value;
  final List<String> reasons;
  const MusicMatchScore(this.value, this.reasons);
}

List<String> musicSearchQueriesFor(Audio audio);
MusicMatchScore scoreMusicCandidate(
  Audio audio, {
  required String title,
  required String artists,
  required String album,
  int? durationSeconds,
});
String musicCandidateKey({
  required String title,
  required String artists,
  required String album,
});
~~~

- [ ] **Step 1: Write failing normalization and ordering tests**

Create tests with these expectations. Define a local makeAudio helper by copying the existing test fixture constructor from test/library/lyric_search_index_test.dart; do not import another test file.

~~~
dart
test('builds bounded queries from title, artist and album', () {
  final audio = makeAudio('song.flac', 1)
    ..title = '01 红豆 (Live) feat. 王菲'
    ..artist = '王菲'
    ..album = '唱游';

  expect(musicSearchQueriesFor(audio), [
    '红豆 王菲',
    '红豆',
    '红豆 唱游',
  ]);
});

test('exact title and artist outrank a version conflict', () {
  final audio = makeAudio('song.flac', 1)
    ..title = '红豆'
    ..artist = '王菲'
    ..album = '唱游';

  final exact = scoreMusicCandidate(
    audio,
    title: '红豆', artists: '王菲', album: '唱游', durationSeconds: 240,
  );
  final live = scoreMusicCandidate(
    audio,
    title: '红豆 (Live)', artists: '王菲', album: '现场', durationSeconds: 310,
  );

  expect(exact.value, greaterThan(live.value));
  expect(live.reasons, contains('版本不一致'));
});
~~~

- [ ] **Step 2: Run the tests and verify they fail**

Run:

~~~
powershell
flutter test test/lyric/music_match_normalizer_test.dart
~~~

Expected: FAIL because the new file and functions do not exist.

- [ ] **Step 3: Implement pure normalization and score functions**

Use these fixed rules:

1. Trim, lowercase, collapse whitespace, and replace common Chinese/English punctuation with spaces for comparison only.
2. Remove a leading track number such as 01, 01. or 01 - from the title.
3. Extract feat, ft, with, live, remix, 伴奏 and 现场 plus bracketed version words into a normalized version-token set; retain tokens for scoring.
4. Convert comparison forms to simplified Chinese and include the existing full-pinyin forms when comparing Chinese text.
5. musicSearchQueriesFor returns unique non-empty queries in this order: cleaned title + cleaned artist, cleaned title, cleaned title + cleaned album.
6. Compute score as title * 0.60 + artist * 0.20 + album * 0.10 + duration * 0.10 + versionAdjustment, clamp to 0..1, and return Chinese reasons. Title exactness is 1.0, title containment is 0.7, token overlap is proportional; duration is 1.0 within 2 seconds, 0.5 within 5 seconds, otherwise 0. A version conflict subtracts 0.20, a matching version adds 0.05.
7. musicCandidateKey joins normalized title, artists and album with U+001F so cross-source duplicates can be detected without changing displayed values.

- [ ] **Step 4: Run normalization tests and commit**

Run:

~~~
powershell
flutter test test/lyric/music_match_normalizer_test.dart
~~~

Expected: PASS. Commit:

~~~
powershell
git add lib/lyric/music_match_normalizer.dart test/lyric/music_match_normalizer_test.dart
git commit -m "feat: add normalized music lyric matching"
~~~

---

### Task 3: 来源模型、适配器和隔离搜索

**Files:**

- Create: lib/lyric/online_lyric_models.dart
- Modify: lib/music_matcher.dart
- Modify: test/music_matcher_test.dart

**Interfaces:**

~~~
dart
enum OnlineLyricFormat { lrc, krc, qrc }

class OnlineLyricPayload {
  final OnlineLyricFormat format;
  final String lyricText;
  final String? translationText;
  const OnlineLyricPayload(this.format, this.lyricText, [this.translationText]);
}

abstract interface class OnlineLyricProvider {
  ResultSource get source;
  Future<List<SongSearchResult>> search(String query, Audio audio);
  Future<OnlineLyricPayload?> fetch(SongSearchResult candidate);
}

Future<List<SongSearchResult>> uniSearch(
  Audio audio, {
  Iterable<OnlineLyricProvider>? providers,
});
~~~

music_matcher.dart must export ResultSource, SongSearchResult, OnlineLyricFormat, OnlineLyricPayload and OnlineLyricProvider so existing imports remain valid.

- [ ] **Step 1: Write failing provider-isolation and malformed-response tests**

Add a fake provider and cover:

~~~
dart
test('one failed provider does not suppress other candidates', () async {
  final audio = makeAudio('song.flac', 1);
  final results = await uniSearch(audio, providers: [
    FakeProvider(
      ResultSource.qq,
      search: (_, __) => throw StateError('qq unavailable'),
    ),
    FakeProvider(
      ResultSource.netease,
      search: (_, __) async => [candidate('红豆', '王菲', '唱游')],
    ),
  ]);

  expect(results, hasLength(1));
  expect(results.single.source, ResultSource.netease);
});
~~~

Also return one malformed row followed by a valid row and assert only the valid row is returned.

Define FakeProvider as an OnlineLyricProvider with a ResultSource source, a Future<List<SongSearchResult>> Function(String, Audio) search callback, and an optional Future<OnlineLyricPayload?> Function(SongSearchResult) fetch callback. Define candidate(title, artists, album, {int? id}) to construct a SongSearchResult with the provider source and the corresponding provider ID.

- [ ] **Step 2: Run matcher tests and verify they fail**

Run:

~~~
powershell
flutter test test/music_matcher_test.dart
~~~

Expected: FAIL because the injectable provider interface and resilient search do not exist.

- [ ] **Step 3: Move public result types without changing call sites**

Move ResultSource and SongSearchResult definitions into online_lyric_models.dart, add the payload and provider interface, and add an export from music_matcher.dart. Keep the existing positional SongSearchResult constructor fields in the same order; preserve the existing fromQQSearchResult, fromNeteaseSearchResult and fromKugouSearchResult factory signatures so current callers remain source-compatible. Add only optional named fields durationSeconds and matchReasons. Keep matchReasons mutable so the matcher can attach the final score explanation after constructing a provider row; all other display fields remain read-only after construction.

- [ ] **Step 4: Implement the three default adapters**

Implement private adapters in music_matcher.dart that retain the current music_api calls:

- QQ: QQ.search(keyWord: query, size: 10) and QQ.songLyric3(songId: id); map name, singer names, album title and ID.
- 酷狗: KuGou.searchSong(keyword: query, size: 10) and KuGou.krc(hash: hash); map songname, singername, album_name, hash and any available duration field.
- 网易云: Netease.search(keyWord: query, size: 10) and Netease.lyric(id: id); map name, artist names, album name and ID.

Every map access checks its type before reading nested fields. A malformed row is skipped and logged with the provider name; it does not throw out the provider's other rows.

- [ ] **Step 5: Implement bounded, isolated uniSearch**

For each provider, run its own safe provider search with an 8-second timeout. Use the query list from musicSearchQueriesFor: issue the first query, issue the title-only query only when the first response has fewer than 5 candidates, and issue the album query only when both previous responses are empty. Limit each provider to 10 rows, score every row with scoreMusicCandidate, deduplicate by musicCandidateKey, sort by descending score and then source name, and return the merged list. A provider error returns an empty list while Future.wait continues collecting other providers.

- [ ] **Step 6: Run matcher tests and commit**

Run:

~~~
powershell
flutter test test/music_matcher_test.dart
~~~

Expected: PASS. Commit:

~~~
powershell
git add lib/lyric/online_lyric_models.dart lib/music_matcher.dart test/music_matcher_test.dart
git commit -m "feat: isolate online lyric providers"
~~~

---

### Task 4: 在线歌词 payload 缓存和正文解析

**Files:**

- Create: lib/lyric/online_lyric_cache.dart
- Create: test/lyric/online_lyric_cache_test.dart
- Modify: lib/music_matcher.dart

**Interfaces:**

~~~
dart
class OnlineLyricCacheEntry {
  final String key;
  final String audioFingerprint;
  final OnlineLyricPayload payload;
  final String title;
  final String artists;
  final String album;
  final double score;
  final int fetchedAtMs;
  const OnlineLyricCacheEntry({
    required this.key,
    required this.audioFingerprint,
    required this.payload,
    required this.title,
    required this.artists,
    required this.album,
    required this.score,
    required this.fetchedAtMs,
  });
}

class OnlineLyricCache {
  OnlineLyricCache({
    required Future<String?> Function() read,
    required Future<void> Function(String contents) write,
    int maxEntries = 200,
  });

  factory OnlineLyricCache.defaults();
  Future<OnlineLyricCacheEntry?> readEntry(
    String key, {
    required String audioFingerprint,
  });
  Future<void> writeEntry(OnlineLyricCacheEntry entry);
}
~~~

- [ ] **Step 1: Write failing cache tests**

Cover these cases:

~~~
dart
test('round trips a payload and rejects a different audio fingerprint', () async {
  String? contents;
  final cache = OnlineLyricCache(
    read: () async => contents,
    write: (value) async => contents = value,
  );
  final entry = makeCacheEntry('qq:1', fingerprint: 'a');

  await cache.writeEntry(entry);
  expect(
    (await cache.readEntry('qq:1', audioFingerprint: 'a'))!.payload.lyricText,
    entry.payload.lyricText,
  );
  expect(await cache.readEntry('qq:1', audioFingerprint: 'b'), isNull);
});
~~~

Also initialize the cache with broken JSON and write 205 entries; assert the stored envelope has exactly 200 entries and no exception escapes.

- [ ] **Step 2: Run cache tests and verify they fail**

Run:

~~~
powershell
flutter test test/lyric/online_lyric_cache_test.dart
~~~

Expected: FAIL because the cache types do not exist.

- [ ] **Step 3: Implement versioned JSON and atomic default storage**

Use envelope { version: 1, entries: { key: { ... } } }. Serialize payload format as lrc, krc or qrc, preserve the optional translation string, and use fetchedAtMs for both the 30-day age check and pruning. defaults() stores online_lyric_cache.json under getAppDataDir(), writes to .tmp with flush true, replaces the current file and restores the old file if replacement fails. On malformed JSON, clear the in-memory map and return null.

- [ ] **Step 4: Add payload parsing and cache lookup to the matcher**

Add these private functions to music_matcher.dart:

~~~
dart
String audioLyricFingerprint(Audio audio) =>
    audio.path + '|' + audio.modified.toString() + '|' +
    audio.title + '|' + audio.artist + '|' + audio.album;

Lyric? parseOnlineLyricPayload(OnlineLyricPayload payload);
~~~

parseOnlineLyricPayload maps lrc to Lrc.fromLrcText with the separator ┃, concatenating a non-empty translationText after lyricText so equal timestamps become primary┃translation; maps krc to Krc.fromKrcText and qrc to Qrc.fromQrcText(lyricText, translationText). Return null for empty text or a parser result with no lines. getOnlineLyric first checks the cache by source plus provider ID/hash and the current audio fingerprint; when audio is null it uses an empty fingerprint and skips fingerprint validation. After a successful provider fetch and parse it writes the payload and candidate metadata.

- [ ] **Step 5: Run cache and existing lyric parser tests and commit**

Run:

~~~
powershell
flutter test test/lyric/online_lyric_cache_test.dart test/lyric/lrc_parser_test.dart test/lyric/ttml_test.dart
~~~

Expected: PASS. Commit:

~~~
powershell
git add lib/lyric/online_lyric_cache.dart test/lyric/online_lyric_cache_test.dart lib/music_matcher.dart
git commit -m "feat: cache parsed online lyric payloads"
~~~

---

### Task 5: 自动候选、正文失败回退和来源窗口

**Files:**

- Modify: lib/music_matcher.dart
- Modify: lib/play_service/lyric_service.dart:158-168
- Modify: lib/page/now_playing_page/component/lyric_source_view.dart:188-327
- Modify: test/music_matcher_test.dart
- Modify: test/component/lyric_source_view_test.dart

**Interfaces:**

~~~
dart
Future<Lyric?> getOnlineLyric({
  Audio? audio,
  SongSearchResult? candidate,
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
  Iterable<OnlineLyricProvider>? providers,
  OnlineLyricCache? cache,
});

Future<Lyric?> getMostMatchedLyric(
  Audio audio, {
  Iterable<OnlineLyricProvider>? providers,
  OnlineLyricCache? cache,
});

String lyricSourceMatchSummary(SongSearchResult result);
~~~

- [ ] **Step 1: Write the failing fallback test**

Add fake providers where the first candidate returns an invalid payload and the second returns valid LRC:

~~~
dart
test('automatic selection falls back when the best lyric body fails', () async {
  final audio = makeAudio('song.flac', 1);
  final lyric = await getMostMatchedLyric(audio, providers: [
    FakeProvider(
      ResultSource.qq,
      search: (_, __) async => [candidate('红豆', '王菲', '唱游', id: 1)],
      fetch: (_) async => const OnlineLyricPayload(OnlineLyricFormat.qrc, ''),
    ),
    FakeProvider(
      ResultSource.netease,
      search: (_, __) async => [candidate('红豆', '王菲', '唱游', id: 2)],
      fetch: (_) async => const OnlineLyricPayload(
        OnlineLyricFormat.lrc,
        '[00:01.00]valid',
      ),
    ),
  ], cache: memoryCache());

  expect(lyric, isNotNull);
  expect((lyric!.lines.single as UnsyncLyricLine).content, 'valid');
});
~~~

- [ ] **Step 2: Run matcher tests and verify the fallback test fails**

Run:

~~~
powershell
flutter test test/music_matcher_test.dart
~~~

Expected: FAIL because getMostMatchedLyric still fetches only the first result.

- [ ] **Step 3: Implement candidate-aware fetch and bounded fallback**

When candidate is supplied, derive its provider ID and use the matching adapter. When only an ID/hash is supplied, select the matching default adapter, preserving the existing call shape. In getMostMatchedLyric, call uniSearch, iterate at most 8 sorted candidates, call getOnlineLyric with the candidate and current audio, and return the first non-null lyric with at least one line. Catch and log each candidate failure without stopping the loop. Do not write LYRIC_SOURCES during automatic selection.

- [ ] **Step 4: Add source summary and resilient candidate tiles**

Implement lyricSourceMatchSummary from matchReasons, showing source and score in Chinese. In _SetLyricSourceDialog, keep the existing local option and candidate list; pass audio into getOnlineLyric, show the summary beside each candidate, and render a compact failure state only for that candidate. Keep the current tap behavior that sets LYRIC_SOURCES[audio.path] and calls useSpecificLyric.

The candidate list must retain each source's deduplicated options. Do not replace it with only the automatically selected item.

- [ ] **Step 5: Pass current audio to explicit online loads**

In LyricService.updateLyric, call getOnlineLyric(audio: nowPlaying, ...) for a saved source. In _LyricSourceTile, call getOnlineLyric(audio: widget.audio, candidate: widget.searchResult). Leave useOnlineLyric() on getMostMatchedLyric(nowPlaying) so automatic fallback remains active.

- [ ] **Step 6: Add pure source-window tests and run the focused suite**

Add a match summary test:

~~~
dart
test('match summary contains source and reasons', () {
  final result = candidate('红豆', '王菲', '唱游');
  result.matchReasons = const ['标题一致', '艺术家一致'];

  expect(lyricSourceMatchSummary(result), contains('标题一致'));
});
~~~

Run:

~~~
powershell
flutter test test/music_matcher_test.dart test/component/lyric_source_view_test.dart test/play_service/desktop_lyric_service_test.dart
~~~

Expected: PASS. Commit:

~~~
powershell
git add lib/music_matcher.dart lib/play_service/lyric_service.dart lib/page/now_playing_page/component/lyric_source_view.dart test/music_matcher_test.dart test/component/lyric_source_view_test.dart
git commit -m "feat: auto-select and fall back across lyric candidates"
~~~

---

### Task 6: 兼容说明、端到端回归和完成前验证

**Files:**

- Modify: README.md
- Test: existing local lyric, matcher, source-window and playback tests

- [ ] **Step 1: Update user-facing documentation**

In the local lyric section, state that Lyrics, LYRICS and LYRIC are accepted for embedded tags, while the value still needs timestamped LRC or TTML content. In the online lyric section, state that playback automatically selects the highest-scoring valid candidate, retries lower candidates when the body fails, and exposes the remaining candidates through “指定默认歌词”. State that online results are cached in the application data directory and are not written into audio files.

- [ ] **Step 2: Run format and targeted tests**

Run:

~~~
powershell
dart format --output=none --set-exit-if-changed lib/lyric/online_lyric_models.dart lib/lyric/music_match_normalizer.dart lib/lyric/online_lyric_cache.dart lib/music_matcher.dart lib/library/lyric_search_index.dart lib/play_service/lyric_service.dart lib/page/now_playing_page/component/lyric_source_view.dart test/lyric/music_match_normalizer_test.dart test/lyric/online_lyric_cache_test.dart test/music_matcher_test.dart test/library/lyric_search_index_test.dart test/component/lyric_source_view_test.dart
flutter test test/lyric test/library/lyric_search_index_test.dart test/music_matcher_test.dart test/component/lyric_source_view_test.dart test/play_service/desktop_lyric_service_test.dart
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo test --manifest-path rust/Cargo.toml
~~~

Expected: all commands exit 0; no existing LRC, TTML, KRC or QRC test regresses.

- [ ] **Step 3: Run scoped static analysis and diff checks**

Run:

~~~
powershell
flutter analyze lib/music_matcher.dart lib/lyric lib/library/lyric_search_index.dart lib/play_service/lyric_service.dart lib/page/now_playing_page/component/lyric_source_view.dart test
git diff --check
git status --short --branch
~~~

Expected: no new analyzer errors, no whitespace errors, and only the planned files changed. Confirm no call to an audio-tag write API was introduced.

- [ ] **Step 4: Perform manual acceptance with a copy of the user's LYRIC file**

Use a disposable copy of one FLAC containing the timestamped LYRIC field. After the library detects the updated mtime, verify local lyrics appear without renaming the tag. Temporarily make one online provider unavailable or use the fake-provider tests to verify other sources still return; play a song with multiple candidates and verify the highest match loads automatically while “指定默认歌词” still lists alternatives.

- [ ] **Step 5: Review the complete diff and commit documentation**

Run:

~~~
powershell
git diff --stat
git diff -- README.md docs/superpowers/specs/2026-09-04-lyrics-online-search-local-tag-compatibility-design.md
git commit -am "docs: document lyric search and local tag compatibility"
~~~

Do not create a release or push a remote tag in this plan; wait for the user to approve the verified implementation and version bump.

## Completion Checklist

- [ ] LYRIC and LYRICS values are read locally and invalid values fall through to the next source.
- [ ] Actual audio mtime changes refresh only the affected lyric-index entry.
- [ ] Three online providers are isolated, bounded and defensively parsed.
- [ ] Normalized score favors the correct title/artist/version and exposes reasons.
- [ ] Automatic matching retries up to eight candidates and returns the first valid lyric.
- [ ] Candidate switching remains available and manual choices keep existing persistence semantics.
- [ ] Cache is versioned, fingerprinted, bounded to 200 entries and never writes audio files.
- [ ] Targeted Flutter and Rust tests, formatting, analysis and git diff --check pass.
