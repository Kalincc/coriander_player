# 选择歌词源与在线搜索诊断 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让歌词来源选择窗口显示缓存候选和 QQ/酷狗/网易云的搜索状态，并用“选择歌词源”消除旧文案歧义。

**Architecture:** 保留 `uniSearch` 的候选列表接口，新增 `searchOnlineLyrics` 返回候选与逐来源诊断状态。报告会将有效缓存项还原为可点击的 `SongSearchResult`，窗口复用现有正文获取和逐曲来源持久化逻辑。

**Tech Stack:** Flutter/Dart、现有 `music_matcher.dart`、`OnlineLyricCache`、Flutter test。

## Global Constraints

- 默认来源仍为 QQ 音乐、酷狗音乐和网易云音乐。
- 不改变自动在线匹配、缓存 TTL、音频标签读取或逐曲来源存储格式。
- 不把在线歌词写回音频文件。
- 先写失败测试，再实现最小行为并运行定向测试。

---

### Task 1: 搜索报告与缓存候选

**Files:**
- Modify: `lib/lyric/online_lyric_models.dart`
- Modify: `lib/music_matcher.dart`
- Test: `test/music_matcher_test.dart`

**Interfaces:**
- `Future<OnlineLyricSearchReport> searchOnlineLyrics(Audio audio, {Iterable<OnlineLyricProvider>? providers, OnlineLyricCache? cache, Duration providerTimeout = const Duration(seconds: 8)})`
- `OnlineLyricSearchReport.candidates` returns cache and live candidates without duplicate provider IDs.
- `OnlineLyricSearchReport.statuses` contains one `LyricProviderSearchStatus` per active provider.

- [ ] **Step 1: Write the failing report tests**

Add tests that assert a failed QQ provider is reported while a valid NetEase candidate remains, and that a valid cached `qq:1` entry appears as a candidate marked `fromCache` when live search returns no rows.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run `flutter test test/music_matcher_test.dart`. Expected: compile failure because the report types and function do not exist.

- [ ] **Step 3: Implement report models and provider outcomes**

Add status/state models, refactor the internal provider search to retain error details, and implement `searchOnlineLyrics`. Keep `uniSearch` delegating to the same live search path without adding cache rows.

- [ ] **Step 4: Implement cached candidate reconstruction**

Read valid entries for the current audio fingerprint, parse `source:id` cache keys, use current audio metadata when cached metadata is empty, set `fromCache: true`, and merge cache rows before live rows while deduplicating by source provider ID.

- [ ] **Step 5: Run the focused matcher tests**

Run `flutter test test/music_matcher_test.dart`; expected: all tests pass, including the new report tests.

### Task 2: 选择歌词源窗口与文案

**Files:**
- Modify: `lib/page/now_playing_page/component/lyric_source_view.dart`
- Modify: `test/component/lyric_source_view_test.dart`
- Modify: `README.md`

- [ ] **Step 1: Write the failing UI helper tests**

Add tests for the provider status label and cached match summary. Assert the status text includes the Chinese source name, candidate count or “无有效结果”, and the failure detail when present.

- [ ] **Step 2: Run the focused UI tests and verify they fail**

Run `flutter test test/component/lyric_source_view_test.dart`; expected: compile failure for the new status-label helper or failed assertions.

- [ ] **Step 3: Render the report in the dialog**

Replace the dialog future with `searchOnlineLyrics(audio)`, show compact status chips with tooltips, show a clear empty state, and keep each cache/live candidate as the existing clickable tile. Append “已缓存” to cached candidate summaries.

- [ ] **Step 4: Rename the user-facing labels**

Change the menu item and dialog heading to “选择歌词源”; update the README section and behavior description to use the new name.

- [ ] **Step 5: Run formatting and focused UI tests**

Run `dart format --output=none --set-exit-if-changed lib/lyric/online_lyric_models.dart lib/music_matcher.dart lib/page/now_playing_page/component/lyric_source_view.dart test/music_matcher_test.dart test/component/lyric_source_view_test.dart` and `flutter test test/music_matcher_test.dart test/component/lyric_source_view_test.dart`.

### Task 3: Regression verification

**Files:**
- No additional files.

- [ ] **Step 1: Run lyric and playback regression tests**

Run `flutter test test/lyric test/play_service/desktop_lyric_service_test.dart`.

- [ ] **Step 2: Run analyzer and diff checks**

Run `flutter analyze lib/music_matcher.dart lib/lyric lib/page/now_playing_page/component/lyric_source_view.dart test/music_matcher_test.dart test/component/lyric_source_view_test.dart`, `git diff --check`, and `git status --short --branch`.

- [ ] **Step 3: Review the final diff**

Confirm only the planned files and the two workflow documents changed; confirm no audio-tag write API was added and no release/push is performed in this task.
