# A 路线：播放队列、播放历史与听歌报告 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不引入在线服务或数据库的前提下，为 Coriander Player 增加可持久化播放队列、受保护的“我喜欢”歌单、最近 12 个月播放历史、可靠增量扫描和周/月 Top 10 听歌报告。

**Architecture:** 沿用现有 JSON 文件和 `Documents\\coriander_player` 数据目录，增加可注入的本地 JSON 原子存储层，并将歌单、队列、历史、报告聚合和音乐库更新分别放在独立的 Dart 服务中。`PlaybackService` 继续负责 BASS 播放，通过明确接口通知队列与历史服务；Rust `update_index` 继续负责底层扫描，Dart 协调器负责重载库、刷新歌词索引和清理失效路径。

**Tech Stack:** Flutter/Dart 3.1+、现有 Material 3 组件、`ChangeNotifier`/`ValueNotifier`、Rust 2021 + `serde_json` + `flutter_rust_bridge`、现有 `AudioLibrary`/`PlaybackService`/`Playlist` 模型；不新增第三方依赖。

## Global Constraints

- 仅处理本地音乐和本地统计；不得新增在线搜索、推荐、云同步、网络请求或插件市场。
- 所有用户数据保存在 `Documents\\coriander_player`，不写入安装目录。
- 队列重启后恢复但不自动播放；已不存在的文件从队列、歌单和历史关联中清理，不删除用户音乐文件。
- “我喜欢”是唯一受保护系统歌单：首次启动创建，旧版本同名歌单合并，禁止删除和改名；普通歌单行为保持不变。
- 队列按完整路径去重，支持队尾、下一首、拖动排序、移除和清空。
- 播放达到 30 秒或歌曲时长 50%（先达到者）才计为有效播放；历史原始事件保留最近 12 个月，历史页面只显示最近 20 条。
- 报告按本地时间支持当前周、当前月和最近 12 个月历史周期；歌曲、歌手、专辑各只展示 Top 10，并显示听歌时长和有效播放次数。
- JSON 文件必须包含 `version` 字段；写入使用 `.tmp` 替换正式文件并保留 `.bak` 恢复路径。
- 不修改音频文件、嵌入歌词、在线歌词缓存或现有 B1 歌词搜索格式。
- 每个任务执行最小必要的 TDD 红/绿测试和一次定向复审；不在任务间重复运行无关的全量测试，最终只运行一次全量 Flutter 测试。

---

## 文件结构与职责

### 计划新增文件

- `lib/library/local_json_store.dart`：可注入数据目录的 JSON 读取、版本读取和原子写入。
- `lib/play_service/playback_queue_service.dart`：路径持久化、队列去重/编辑、当前歌曲和失效路径清理。
- `lib/library/playback_history_models.dart`：播放事件、周期、排名和报告值对象。
- `lib/play_service/playback_history_service.dart`：有效播放会话、12 个月保留和最近历史查询。
- `lib/library/listening_report.dart`：纯函数式周/月 Top 10 聚合。
- `lib/library/library_update_coordinator.dart`：扫描、音乐库重载、歌词索引刷新和应用内路径清理的协调接口。
- `lib/component/now_playing_favorite_button.dart`：正在播放歌曲的“我喜欢”切换按钮。
- `lib/page/listening_report_page.dart`：周期选择、摘要卡片和 Top 10 报告页面。

### 计划修改文件

- `lib/library/playlist.dart`：系统歌单字段、旧数据迁移、读写清理和“我喜欢”操作。
- `lib/play_service/play_service.dart`、`lib/play_service/playback_service.dart`：注入队列/历史服务并转发播放生命周期。
- `lib/page/now_playing_page/component/current_playlist_view.dart`：队列编辑 UI。
- `lib/page/now_playing_page/page.dart`、`lib/page/now_playing_page/large_page.dart`、`lib/component/mini_now_playing.dart`：爱心按钮入口和恢复状态显示。
- `lib/page/playlists_page.dart`、`lib/page/playlist_detail_page.dart`、`lib/page/uni_page_components.dart`：保护系统歌单、保存迁移后的歌单。
- `lib/src/rust/api/tag_reader.dart`、`rust/src/api/tag_reader.rs`：增量扫描的 Dart 接口注释和 Rust 实现。
- `lib/page/updating_page.dart`、`lib/page/settings_page/other_settings.dart`、`lib/app_paths.dart`、`lib/entry.dart`、`lib/component/side_nav.dart`：更新协调、手动扫描、报告路由和左侧导航。
- `README.md`：补充本地数据目录、升级保留规则和 A 路线功能说明。

### 计划新增/修改测试文件

- `test/library/local_json_store_test.dart`
- `test/library/playlist_test.dart`
- `test/play_service/playback_queue_service_test.dart`
- `test/library/playback_history_models_test.dart`
- `test/play_service/playback_history_service_test.dart`
- `test/library/listening_report_test.dart`
- `test/library/library_update_coordinator_test.dart`
- `test/component/now_playing_favorite_button_test.dart`
- `test/component/current_playlist_view_test.dart`
- `test/page/listening_report_page_test.dart`
- `rust/src/api/tag_reader.rs` 内的纯路径/索引差异单元测试（不启动 Flutter UI）。

---

## Task 1: 本地 JSON 原子存储与“我喜欢”歌单迁移

**Files:**
- Create: `lib/library/local_json_store.dart`
- Modify: `lib/library/playlist.dart`
- Test: `test/library/local_json_store_test.dart`, `test/library/playlist_test.dart`

**Interfaces:**
- Produces `LocalJsonStore(Directory directory)`, `Future<Object?> read(String fileName)` and `Future<void> writeAtomically(String fileName, Object value)`。
- Produces `const likedPlaylistName = '我喜欢'`、`Future<void> ensureLikedPlaylist()`、`bool isLiked(Audio audio)` and `Future<void> toggleLiked(Audio audio)`。
- `Playlist` 保留现有 `Playlist(String name, Map<String, Audio> audios)` 调用兼容性，增加 `bool isSystem` 可选字段；`toMap/fromMap` 兼容缺少该字段的旧 JSON。

- [ ] **Step 1: 写本地存储的失败测试**

  在临时目录中验证 `read` 能读取 JSON、缺失文件返回 `null`；验证 `writeAtomically` 先写临时文件、成功替换正式文件，并在替换失败时保留 `.bak` 可恢复。

- [ ] **Step 2: 运行存储测试确认 RED**

  Run: `flutter test test/library/local_json_store_test.dart`

  Expected: FAIL，因为 `LocalJsonStore` 尚未存在。

- [ ] **Step 3: 实现最小存储层**

  `LocalJsonStore.read` 使用 `json.decode`，`writeAtomically` 使用 `<name>.tmp` 和 `<name>.bak`，创建目录后写入 UTF-8 JSON；正式文件存在时先改名为备份，临时文件再改名为正式文件，异常时恢复备份。

- [ ] **Step 4: 写歌单迁移和系统歌单失败测试**

  覆盖旧 JSON 缺少 `isSystem`、首次创建“我喜欢”、两个同名歌单合并、系统歌单不能改名/删除，以及 `readPlaylists` 重复调用不会累加全局列表。

- [ ] **Step 5: 实现歌单迁移和爱心操作**

  在 `Playlist` 增加 `isSystem`；`readPlaylists` 读取后清空旧列表并调用 `ensureLikedPlaylist`；迁移时按路径合并同名歌单，只保留一个 `isSystem=true` 实例；`savePlaylists` 改用 `LocalJsonStore`；系统歌单的编辑和删除入口由 UI 依据 `isSystem` 禁用。

- [ ] **Step 6: 运行 Task 1 定向测试并提交**

  Run: `flutter test test/library/local_json_store_test.dart test/library/playlist_test.dart`

  Expected: 所有测试通过。

  Commit: `feat: add local storage and protected liked playlist`

---

## Task 2: 持久化播放队列服务

**Files:**
- Create: `lib/play_service/playback_queue_service.dart`
- Modify: `lib/play_service/playback_service.dart`, `lib/play_service/play_service.dart`
- Test: `test/play_service/playback_queue_service_test.dart`

**Interfaces:**
- `PlaybackQueueService({required LocalJsonStore store})` extends `ChangeNotifier`。
- `UnmodifiableListView<Audio> get items`、`String? get currentPath`、`Duration get savedPosition`、`int get currentIndex`。
- `Future<void> load(Iterable<Audio> library)` 从路径 JSON 解析当前库歌曲并丢弃失效/重复路径。
- `Future<void> setQueue(Iterable<Audio> items, {String? currentPath, Duration position = Duration.zero})`。
- `Future<bool> append(Audio audio)`、`Future<bool> insertNext(Audio audio)`、`Future<bool> removeAt(int index)`、`Future<void> reorder(int oldIndex, int newIndex)`、`Future<void> clear()`、`Future<void> reconcile(Iterable<Audio> library)`。
- `Future<void> setCurrent({required Audio? audio, required Duration position})` 保存当前路径和位置但不启动播放器。

- [ ] **Step 1: 写队列模型和持久化的 RED 测试**

  在临时 `LocalJsonStore` 上验证 JSON 往返、路径解析、去重、失效路径丢弃、旧版本缺字段默认值和当前歌曲位置恢复。

- [ ] **Step 2: 运行队列测试确认 RED**

  Run: `flutter test test/play_service/playback_queue_service_test.dart`

  Expected: FAIL，因为队列服务和数据格式尚未实现。

- [ ] **Step 3: 实现队列服务**

  内存状态只保存 `Audio` 对象和路径；写 JSON 时只写路径、`currentPath`、`positionMs`；所有添加入口按路径去重；`reorder` 对 `oldIndex < newIndex` 先减一；清理后若当前路径不存在则清空当前状态并保存。

- [ ] **Step 4: 让 PlaybackService 通过队列服务保持兼容**

  `PlayService` 初始化 `playbackQueueService`；`PlaybackService.playlist` 继续作为兼容的 `ValueNotifier<List<Audio>>` 暴露给现有页面，但由队列服务变更同步更新。现有 `play`、`shuffleAndPlay`、`addToNext`、`playIndexOfPlaylist` 和自动下一首逻辑改为调用队列 API，保持播放模式语义不变。

- [ ] **Step 5: 运行 Task 2 定向回归并提交**

  Run: `flutter test test/play_service/playback_queue_service_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart`

  Expected: 队列测试和现有歌词相关回归全部通过。

  Commit: `feat: add persistent playback queue`

---

## Task 3: 播放历史会话与 Top 10 聚合

**Files:**
- Create: `lib/library/playback_history_models.dart`, `lib/play_service/playback_history_service.dart`, `lib/library/listening_report.dart`
- Modify: `lib/play_service/play_service.dart`
- Test: `test/library/playback_history_models_test.dart`, `test/play_service/playback_history_service_test.dart`, `test/library/listening_report_test.dart`

**Interfaces:**
- `PlaybackHistoryEvent({required String path, required DateTime startedAt, required Duration listened, required bool qualified})`，提供 `toMap/fromMap`。
- `PlaybackHistoryService({required LocalJsonStore store, DateTime Function()? now})` extends `ChangeNotifier`，提供 `Future<void> load()`、`void startSession(Audio audio, {DateTime? startedAt})`、`void recordPosition(Duration position)`、`Future<void> endSession()`、`List<PlaybackHistoryEvent> get recent20`、`List<PlaybackHistoryEvent> get events`。
- `ReportPeriod` 表示本地时间范围，提供 `ReportPeriod.currentWeek(DateTime now)`、`ReportPeriod.currentMonth(DateTime now)` 和历史周期构造方法。
- `ListeningReport buildListeningReport(Iterable<PlaybackHistoryEvent> events, ReportPeriod period, Map<String, Audio> metadata)` 返回总时长、有效次数、歌曲/歌手/专辑数量及三个 `List<ListeningRank>`，每个列表最多 10 项。

- [ ] **Step 1: 写事件、门槛和聚合 RED 测试**

  测试 29 秒不计入、30 秒计入、短歌达到 50% 计入、暂停/切歌结束保存实际时长、超过 12 个月清理、最近 20 条倒序、周一周日边界、跨月/跨年和 Top 10 截断。

- [ ] **Step 2: 运行历史测试确认 RED**

  Run: `flutter test test/library/playback_history_models_test.dart test/play_service/playback_history_service_test.dart test/library/listening_report_test.dart`

  Expected: FAIL，因为事件、服务和聚合函数尚未存在。

- [ ] **Step 3: 实现值对象和纯聚合函数**

  报告聚合只使用事件时间范围和当前 `Audio` 元数据；歌曲按路径聚合，歌手按原始艺术家名称聚合，专辑按专辑名称聚合；排序先按播放次数降序、再按收听时长降序、最后按名称升序，稳定截取前 10。

- [ ] **Step 4: 实现历史服务和原子持久化**

  `startSession` 创建单个会话，`recordPosition` 记录最大已听位置；`endSession` 以 `max(30 秒, duration * 0.5)` 的先达到逻辑计算资格，合格才写入事件，并清理 12 个月前记录。暂停后结束当前会话，恢复播放时建立新会话；写入失败只记录日志并保留内存状态。

- [ ] **Step 5: 运行 Task 3 定向测试并提交**

  Run: `flutter test test/library/playback_history_models_test.dart test/play_service/playback_history_service_test.dart test/library/listening_report_test.dart`

  Expected: 所有事件、门槛、留存和 Top 10 测试通过。

  Commit: `feat: record local playback history and listening reports`

---

## Task 4: 播放生命周期、队列编辑和“我喜欢”入口

**Files:**
- Modify: `lib/play_service/playback_service.dart`, `lib/play_service/play_service.dart`, `lib/page/now_playing_page/component/current_playlist_view.dart`, `lib/page/now_playing_page/page.dart`, `lib/page/now_playing_page/large_page.dart`, `lib/component/mini_now_playing.dart`, `lib/page/playlists_page.dart`, `lib/page/playlist_detail_page.dart`, `lib/page/uni_page_components.dart`
- Create: `lib/component/now_playing_favorite_button.dart`
- Test: `test/component/now_playing_favorite_button_test.dart`, `test/component/current_playlist_view_test.dart`

**Interfaces:**
- `PlaybackService` 通过 `playbackHistoryService.startSession`, `recordPosition` 和 `endSession` 通知播放生命周期；不让 UI 直接写历史文件。
- `NowPlayingFavoriteButton` 接收 `Audio? audio`，从歌单仓库读取当前状态，点击调用 `toggleLiked` 并通过 `Listenable` 更新图标。

- [ ] **Step 1: 写播放生命周期和 UI RED 测试**

  使用 fake history/queue 服务验证：开始歌曲创建会话，位置流更新会记录位置，暂停/切歌/完成结束会话；队列行可删除/排序/清空；爱心未收藏/已收藏图标和点击状态正确。

- [ ] **Step 2: 运行组件测试确认 RED**

  Run: `flutter test test/component/now_playing_favorite_button_test.dart test/component/current_playlist_view_test.dart`

  Expected: FAIL，因为控件和生命周期接线尚未实现。

- [ ] **Step 3: 接入 PlaybackService 生命周期**

  在 `_loadAndPlay` 切换新歌曲前结束旧会话；加载成功后开始新会话；`positionStream` 同步给历史服务；`pause`、`playAgain`、`close` 和完成事件正确结束/重启会话。所有历史通知必须在播放器状态更新后发出，避免把失败的 `setSource` 记录为播放。

- [ ] **Step 4: 实现队列编辑界面**

  `CurrentPlaylistView` 监听 `PlaybackQueueService`，加入拖动手柄、行尾删除、顶部清空；拖动操作使用 `ReorderableListView`，删除/清空后保留当前索引的一致性；现有点击行播放逻辑保持不变。

- [ ] **Step 5: 接入爱心按钮和系统歌单保护**

  在大屏正在播放信息区域和 `MiniNowPlaying` 放置同一个 `NowPlayingFavoriteButton`；无当前歌曲时禁用；歌单页和歌单详情页对 `isSystem` 歌单隐藏重命名/删除操作；普通歌单仍可编辑。

- [ ] **Step 6: 运行 Task 4 定向回归并提交**

  Run: `flutter test test/component/now_playing_favorite_button_test.dart test/component/current_playlist_view_test.dart test/play_service/playback_queue_service_test.dart test/play_service/playback_history_service_test.dart`

  Expected: 队列、历史生命周期和两个播放界面控件全部通过。

  Commit: `feat: connect playback history queue editing and liked songs`

---

## Task 5: 可靠增量扫描与库更新协调

**Files:**
- Modify: `rust/src/api/tag_reader.rs`, `lib/src/rust/api/tag_reader.dart`, `lib/page/updating_page.dart`, `lib/page/settings_page/other_settings.dart`
- Create: `lib/library/library_update_coordinator.dart`
- Test: Rust `#[cfg(test)]` in `rust/src/api/tag_reader.rs`, `test/library/library_update_coordinator_test.dart`

**Interfaces:**
- 保持现有 `updateIndex({required String indexPath}) -> Stream<IndexActionState>` FRB 签名不变，避免重新生成 Dart bindings；只改变内部索引合并逻辑。
- `LibraryUpdateCoordinator({required Future<Stream<IndexActionState>> Function() scan, required Future<void> Function() reloadLibrary, required Future<void> Function() refreshLyrics, required Future<void> Function() reconcileAppData})` 提供 `Future<void> update()` 和可监听进度状态。

- [ ] **Step 1: 写路径差异和协调器 RED 测试**

  Rust 测试使用临时目录验证递归路径集合对新增、删除和修改文件的分类；Dart fake 测试验证协调顺序为扫描 → 音乐库重载 → 歌词索引刷新 → 队列/歌单/历史清理，且扫描异常不执行破坏性清理。

- [ ] **Step 2: 运行扫描测试确认 RED**

  Run: `cargo test --manifest-path rust/Cargo.toml tag_reader` 和 `flutter test test/library/library_update_coordinator_test.dart`

  Expected: 新增差异和协调器测试在实现前失败；现有未相关 Rust 测试不需要重复运行。

- [ ] **Step 3: 实现 Rust 递归增量合并**

  在 `update_index` 中递归枚举每个已配置目录，建立规范化完整路径集合；删除不存在路径，按路径匹配已有记录，对修改时间/大小变化的文件重新读取标签，对新增路径读取标签后加入；索引为空时保证进度分母至少为 1；使用临时文件替换 `index.json` 并在错误时恢复旧文件。

- [ ] **Step 4: 实现 Dart 更新协调器**

  `LibraryUpdateCoordinator.update` 消费 `updateIndex` 流并转发进度；`onDone` 后依次调用 `AudioLibrary.initFromIndex`、`readPlaylists`/系统歌单迁移、队列 `reconcile`、历史清理和 `LyricSearchIndex.refreshCurrentLibrary`；扫描异常保留旧内存状态并暴露错误，不清理路径。

- [ ] **Step 5: 接入启动和手动扫描入口**

  `UpdatingPage` 使用协调器替代重复的 Future.wait；设置页文件夹管理对话框增加“立即扫描”按钮，复用相同进度视图，扫描结束后关闭对话框而不跳转或播放；保存文件夹设置后仍可执行完整重建索引。

- [ ] **Step 6: 运行 Task 5 定向验证并提交**

  Run: `cargo test --manifest-path rust/Cargo.toml tag_reader`; `flutter test test/library/library_update_coordinator_test.dart test/library/lyric_search_index_test.dart test/page/search_result_page_test.dart`

  Expected: Rust 路径差异、Dart 协调、歌词索引和现有搜索回归通过。

  Commit: `feat: harden incremental library scanning`

---

## Task 6: 听歌报告页面与左侧导航

**Files:**
- Create: `lib/page/listening_report_page.dart`
- Modify: `lib/app_paths.dart`, `lib/entry.dart`, `lib/component/side_nav.dart`
- Test: `test/page/listening_report_page_test.dart`

**Interfaces:**
- 页面消费 Task 3 的 `PlaybackHistoryService`, `ReportPeriod` 和 `ListeningReport`，不直接读取 JSON。
- 新路由 `LISTENING_REPORT_PAGE = '/reports'`；不加入 `START_PAGES`，避免改变用户原有启动页。

- [ ] **Step 1: 写报告页面 RED 测试**

  使用 fake `PlaybackHistoryService` 验证左侧导航出现“听歌报告”、当前周/月切换更新周期、摘要显示总时长和次数、歌曲/歌手/专辑各只渲染前 10 项、空周期显示空状态，点击排名不调用播放方法。

- [ ] **Step 2: 运行页面测试确认 RED**

  Run: `flutter test test/page/listening_report_page_test.dart`

  Expected: FAIL，因为路由、导航和页面尚未存在。

- [ ] **Step 3: 实现报告页面**

  使用 `PageScaffold`、`SegmentedButton` 或 `MenuAnchor` 选择本周/本月/历史周期；摘要使用 `Card`；Top 10 使用 `ListView` 和 `LinearProgressIndicator` 展示相对比例，不添加图表依赖；缺失元数据时显示路径文件名并禁用详情跳转。

- [ ] **Step 4: 接入路由和导航**

  在 `app_paths.dart` 添加常量，在 `entry.dart` 的 `ShellRoute` 添加页面，在 `side_nav.dart` 增加 `Symbols.insights` 与“听歌报告”目的地；`START_PAGES` 保持原五个页面不变。

- [ ] **Step 5: 运行 Task 6 定向测试并提交**

  Run: `flutter test test/page/listening_report_page_test.dart test/library/listening_report_test.dart test/component/now_playing_favorite_button_test.dart`

  Expected: 页面、聚合和爱心入口回归通过。

  Commit: `feat: add listening report navigation and top charts`

---

## Task 7: 数据目录说明、迁移回归与整合验证

**Files:**
- Modify: `README.md`
- Test: `test/library/playlist_test.dart`, `test/play_service/playback_queue_service_test.dart`, `test/play_service/playback_history_service_test.dart`, `test/page/listening_report_page_test.dart`

- [ ] **Step 1: 增加升级与备份说明**

  在 README 的 fork 改动和安装说明中写明：用户数据位于 `Documents\\coriander_player`，重新安装程序不会删除；备份时复制该目录，删除该目录会同时删除歌单、队列和历史。

- [ ] **Step 2: 增加跨版本迁移回归**

  用旧版无 `isSystem` 的 `playlists.json`、缺少队列/历史文件和损坏 `.tmp` 的临时目录启动各服务，断言服务创建可用默认结构、保留旧歌曲并不自动播放。

- [ ] **Step 3: 执行定向整合测试**

  Run:

  ```bash
  flutter test test/library test/play_service test/component/now_playing_favorite_button_test.dart test/component/current_playlist_view_test.dart test/page/listening_report_page_test.dart test/page/search_result_page_test.dart
  ```

  Expected: 所有现有歌单、歌词搜索、队列、历史、报告和导航测试通过。

- [ ] **Step 4: 执行格式、分析和副作用检查**

  Run:

  ```bash
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze lib test
  git diff --check
  rg -n "writeAsString|File\(|http|music_api" lib/play_service lib/library lib/page/listening_report_page.dart
  ```

  Expected: 格式和 diff 检查通过；分析无 error；新增路径没有音频/标签/在线缓存写入。

- [ ] **Step 5: 执行唯一一次最终全量测试并提交**

  Run: `flutter test`

  Expected: 全部测试通过；保留既有非阻塞 info 时在报告中注明，不为了本计划顺手迁移无关 API。

  Commit: `docs: document local playback data and upgrade behavior`

---

## 执行顺序与审查门

1. Task 1 完成后，Task 2 和 Task 3 可分别开发；Task 4 依赖二者。
2. Task 5 可在 Task 2/3 之后接入，因为协调器需要清理队列、歌单和历史路径。
3. Task 6 依赖 Task 3 的报告模型；Task 7 等所有功能接入后执行。
4. 每个任务结束运行该任务列出的最小测试、`dart format` 或 `cargo test`（仅在涉及对应语言时），然后进行一次针对该任务的只读复审。
5. 所有任务完成后生成整分支复审包；只有无 Critical/Important 问题且最终 `flutter test` 通过，才进入合并或 PR 选择。

## 计划自检

- 设计文档中的四类功能均有任务覆盖：队列/我喜欢（Tasks 1–4）、历史/报告（Tasks 3、6）、增量扫描（Task 5）、升级保留和迁移（Tasks 1、7）。
- 数据路径、有效播放门槛、12 个月保留、最近 20 条、Top 10、无自动播放和系统歌单保护均在 Global Constraints 与具体任务中重复明确。
- 任务间接口名称一致：`LocalJsonStore` → `PlaybackQueueService`/`PlaybackHistoryService` → `LibraryUpdateCoordinator`/`ListeningReport` → 页面路由。
- 计划不引入占位词、在线服务或新增依赖；每个任务都有明确文件、RED/GREEN 测试命令和提交点。
