# 桌面歌词切歌信息同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复桌面歌词切歌后标题、歌手、专辑滞后，并让播放器与桌面歌词组件使用可靠的顺序消息协议。

**Architecture:** 播放器使用 FIFO 的换行分帧 JSON 队列，`PlaybackService` 和 `LyricService` 用代次阻止旧歌曲异步回调；发布脚本在构建固定的 `desktop_lyric` 源码时应用 `LineSplitter` 补丁，使子进程按行解析消息。

**Tech Stack:** Flutter/Dart、Dart `Future`/`LineSplitter`、PowerShell、Git worktree、Flutter test/analyze。

## Global Constraints

- 不修改用户音乐文件、歌词缓存、播放历史或设置文件。
- 不改变现有 `desktop_lyric` 消息类型和 JSON 字段，只增加换行分帧与接收端缓冲。
- 补丁必须针对发布脚本固定且与 `pubspec.lock` 一致的 `536be8df55c80a7fdf7cc20f603d3fc76a732821`，目标不匹配时构建失败。
- 每个生产行为变更先写失败测试并观察失败，再写最小实现。

---

### Task 1: 创建播放器端 FIFO 消息队列

**Files:**
- Create: `lib/play_service/desktop_lyric_message_queue.dart`
- Modify: `lib/play_service/desktop_lyric_service.dart`
- Create: `test/play_service/desktop_lyric_message_queue_test.dart`

**Interfaces:**
- Consumes: `desktop_lyric.Message`, `Future<Process?>` readiness and a frame writer.
- Produces: `DesktopLyricMessageQueue.enqueue(Message, {isFrameCurrent})`, which serializes one newline-terminated JSON frame at a time and can recover a failed pipe with a validated playback snapshot.

- [x] **Step 1: Write the failing queue tests**

覆盖以下行为：首条写入延迟时第二条不能抢先；每个写入帧只有一条 JSON 且以换行结束；首条失败后已排队帧被作废；恢复时先发播放状态快照，快照失效或触发帧过期时不再发送旧帧。

- [x] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/play_service/desktop_lyric_message_queue_test.dart`

Expected: FAIL because `DesktopLyricMessageQueue` does not exist.

- [x] **Step 3: Implement the minimal queue**

Use a private `Future<void> _tail` chain and a queue generation. Each `enqueue` appends a callback that invokes the injected `Future<void> Function(String frame)` writer with `message.buildMessageJson() + '\\n'`; a failed write invalidates already queued frames. The next valid frame invokes an optional recovery callback first, and an optional frame guard is checked before and after recovery. Return the individual operation future to callers while keeping the queue usable.

- [x] **Step 4: Integrate the queue into `DesktopLyricService`**

Route `sendMessage` through the queue. The injected writer resolves `desktopLyric`, verifies the process is current, writes the frame to `stdin`, and awaits `flush()`. Increment a process generation when starting or killing the companion so queued frames from a dead process are ignored. On a failed write, recover by capturing and sending current player state plus `NowPlaying` metadata, then only release a frame whose song snapshot is still current.

- [x] **Step 5: Run focused tests**

Run: `flutter test test/play_service/desktop_lyric_message_queue_test.dart test/play_service/desktop_lyric_service_test.dart`

Expected: PASS.

- [x] **Step 6: Commit**

```powershell
git add lib/play_service/desktop_lyric_message_queue.dart lib/play_service/desktop_lyric_service.dart test/play_service/desktop_lyric_message_queue_test.dart
git commit -m "fix: serialize desktop lyric messages"
```

### Task 2: Prevent stale playback and lyric callbacks

**Files:**
- Modify: `lib/play_service/playback_service.dart`
- Modify: `lib/play_service/lyric_service.dart`
- Modify: `test/play_service/desktop_lyric_service_test.dart`
- Modify: `test/page/now_playing_page/lyric_scroll_positioner_test.dart` or create `test/play_service/lyric_service_test.dart`

**Interfaces:**
- Consumes: current `_loadAndPlay` request and lyric source changes.
- Produces: only the latest playback request may send metadata; only the latest lyric generation may send a line.

- [x] **Step 1: Write the failing generation tests**

Add a deferred desktop-message readiness test proving an older playback request cannot send its metadata after a newer request, and a lyric delegate test proving a delayed old line is ignored after `useSpecificLyric` starts a newer generation.

- [x] **Step 2: Run focused tests and verify the expected failures**

Run: `flutter test test/play_service/desktop_lyric_service_test.dart test/play_service/lyric_service_test.dart`

Expected: FAIL because there is no playback/lyric generation guard.

- [x] **Step 3: Implement the smallest guards**

Increment a playback request counter at `_loadAndPlay` entry; capture the local `Audio` and check the counter before sending state/metadata. Increment a lyric generation counter whenever a new lyric future is selected; capture and check it before refresh and before sending a desktop line.

- [x] **Step 4: Run the focused tests**

Run: `flutter test test/play_service/desktop_lyric_service_test.dart test/play_service/lyric_service_test.dart`

Expected: PASS.

- [x] **Step 5: Commit**

```powershell
git add lib/play_service/playback_service.dart lib/play_service/lyric_service.dart test/play_service/desktop_lyric_service_test.dart test/play_service/lyric_service_test.dart
git commit -m "fix: drop stale desktop lyric updates"
```

### Task 3: Patch the desktop lyric receiver and release build

**Files:**
- Create: `scripts/patch_desktop_lyric_protocol.ps1`
- Create: `scripts/tests/desktop_lyric_protocol_test.ps1`
- Modify: `scripts/package_windows.ps1`
- Modify: `README.md`

**Interfaces:**
- Consumes: a checked-out `desktop_lyric` source directory.
- Produces: a patched controller using `LineSplitter`, and a release build that refuses to continue if patching fails.

- [x] **Step 1: Write the failing PowerShell patch test**

Create a temporary fixture containing the pinned controller parser, invoke the patch script, assert `LineSplitter` is present and the direct chunk parser is gone, then invoke the script against a mismatched fixture and assert a non-zero failure.

- [x] **Step 2: Run the script test and verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/desktop_lyric_protocol_test.ps1`

Expected: FAIL because the patch script does not exist.

- [x] **Step 3: Implement the guarded patch script**

Resolve the exact controller path, replace only the known parser block, and throw if the expected source text is absent or already partially modified. Keep the replacement line-buffered and continue after per-line JSON errors.

- [x] **Step 4: Integrate patching into `package_windows.ps1`**

Run the patch script immediately after checkout and before `flutter pub get`; retain the existing pinned commit and fail fast on any patch error.

- [x] **Step 5: Update manual build documentation**

Document the patch command between cloning/checking out `desktop_lyric` and building it, and state that release packages already contain the patched companion.

- [x] **Step 6: Run script tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/desktop_lyric_protocol_test.ps1`

Expected: PASS.

- [x] **Step 7: Commit**

```powershell
git add scripts/patch_desktop_lyric_protocol.ps1 scripts/tests/desktop_lyric_protocol_test.ps1 scripts/package_windows.ps1 README.md
git commit -m "fix: frame desktop lyric protocol"
```

### Task 4: Full verification and review

**Files:**
- Test: all Flutter tests, analyzer, PowerShell release tests, and `git diff --check`.

- [x] **Step 1: Run focused regression tests**

Run: `flutter test test/play_service/desktop_lyric_message_queue_test.dart test/play_service/desktop_lyric_service_test.dart test/play_service/lyric_service_test.dart`

- [x] **Step 2: Run the full Flutter suite**

Run: `flutter test`

- [x] **Step 3: Run analyzer and PowerShell checks**

Run: `flutter analyze --no-fatal-infos lib test`; then run `scripts/tests/desktop_lyric_protocol_test.ps1`, `scripts/tests/release_helpers_test.ps1`, and `scripts/tests/installer_contract_test.ps1`.

- [x] **Step 4: Check the diff**

Run: `git diff --check` and `git status --short --branch`. Restore only Flutter-generated Windows files if test tooling rewrites them.

- [x] **Step 5: Request code review**

Review the complete diff against the previous lyric-source-diagnostics commit and address every Important/Critical finding before reporting completion.
