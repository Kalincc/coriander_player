# 播放器性能与本地库体验改进实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留本地歌词、歌单、我喜欢、播放历史和听歌报告的前提下，消除启动/搜索卡顿，改善封面与报告可视化，并将播放队列和扫描行为恢复为用户可控的旧版语义。

**Architecture:** 先移除持久播放队列和启动扫描这两个高耦合路径，再以共享封面组件和异步搜索控制器承载 UI 改进。音乐库只在首次建库或用户点击“立即扫描”时完整重建；已有索引启动只加载，不扫描、不清理、不刷新歌词。歌词、历史和歌单服务继续使用现有本地 JSON 存储。

**Tech Stack:** Flutter/Dart、原生 Material 3、现有 `Audio.cover`/`ImageProvider`、Flutter Rust Bridge 2.11.1、Rust `tag_reader`，不新增第三方依赖。

## Global Constraints

- 不安装 Cargo/Rust 工具链；Rust 编译验证交给 GitHub Actions。
- 不添加图表或搜索第三方依赖。
- 首次安装必须完整建库；已有索引启动不得调用音乐目录扫描或歌词指纹扫描。
- “文件夹管理 → 立即扫描”只由用户手动触发完整递归重建，成功后才 reload/reconcile/sync。
- 旧 `playback_queue.json` 保留但不删除、不迁移、不读取。
- 单曲播放列表只能包含当前单曲；专辑播放列表必须包含整张专辑。
- 听歌报告 Top 10、最近播放最多 20 条、点击报告项目不得隐式播放。
- 每个任务完成一个最小测试周期后再提交；最终只跑一次相关集合和一次完整 Flutter 测试。

---

### Task 1: 回退播放队列并保留听歌历史

**Files:**
- Modify: `lib/play_service/playback_service.dart`
- Modify: `lib/play_service/play_service.dart`
- Modify: `lib/page/now_playing_page/component/current_playlist_view.dart`
- Modify: `lib/component/audio_tile.dart`
- Modify: `lib/page/welcoming_page.dart`
- Modify: `lib/page/updating_page.dart`
- Delete when no references remain: `lib/play_service/playback_queue_service.dart`
- Test: `test/component/current_playlist_view_test.dart`
- Test: `test/play_service/play_service_initialization_test.dart`
- Test: `test/play_service/playback_history_service_test.dart`

**Interfaces:**
- `PlaybackService.play(int audioIndex, List<Audio> playlist)` 继续以调用方列表替换内存播放列表。
- `PlaybackService.playIndexOfPlaylist(int audioIndex)` 只操作当前内存列表。
- `PlayService.initializePlaybackData(Iterable<Audio> library)` 只加载历史；不得创建或加载 `PlaybackQueueService`。
- `PlayService.reconcilePlaybackData(Iterable<Audio> library)` 只校准历史和歌单，不校准队列。

- [ ] **Step 1: 写回归测试**：让当前播放视图通过注入的 playback service/fake 断言列表只读、点击索引播放；新增纯服务测试断言 `play(0, [song])` 的上下文只有一首，`play(n, album)` 的上下文包含整张专辑；断言初始化 fake 只调用 history loader。
- [ ] **Step 2: 运行 RED**：
  ```powershell
  flutter test --no-pub test/component/current_playlist_view_test.dart test/play_service/play_service_initialization_test.dart
  ```
  预期：由于当前测试仍依赖持久队列注入或 queue loader，按预期失败。
- [ ] **Step 3: 实现最小回退**：从 `PlaybackService` 移除 queue attach、queue JSON 写入、恢复位置、队尾追加、删除/清空方法，恢复旧版 `playlist`/`_playlistBackup` 替换和 shuffle 行为；保留 `PlaybackHistoryService` 的 start/record/end 调用。`CurrentPlaylistView` 恢复只读 `ListView`，`AudioTile` 删除“添加到播放队尾”，保留“下一首播放”。`PlayService` 和 welcoming/updating 启动链路只加载历史。删除不再引用的 queue service 与 queue tests；不触碰磁盘上的 `playback_queue.json`。
- [ ] **Step 4: 运行 GREEN**：
  ```powershell
  flutter test --no-pub test/component/current_playlist_view_test.dart test/play_service/play_service_initialization_test.dart test/play_service/playback_history_service_test.dart
  ```
  预期：队列语义和历史生命周期测试全部通过。
- [ ] **Step 5: 提交**：
  ```powershell
  git add lib/play_service lib/page/now_playing_page/component/current_playlist_view.dart lib/component/audio_tile.dart lib/page/welcoming_page.dart lib/page/updating_page.dart test/component/current_playlist_view_test.dart test/play_service/play_service_initialization_test.dart test/play_service/playback_history_service_test.dart
  git commit -m "fix: restore in-memory playback playlist semantics"
  ```

### Task 2: 收藏状态、歌单封面和共享封面组件

**Files:**
- Create: `lib/component/artwork_thumbnail.dart`
- Modify: `lib/component/now_playing_favorite_button.dart`
- Modify: `lib/library/playlist.dart`
- Modify: `lib/component/audio_tile.dart`
- Modify: `lib/page/playlists_page.dart`
- Modify: `lib/page/playlist_detail_page.dart`
- Test: `test/component/now_playing_favorite_button_test.dart`
- Test: `test/library/playlist_test.dart`
- Test: `test/component/artwork_thumbnail_test.dart`

**Interfaces:**
- `ArtworkThumbnail({required Future<ImageProvider?>? image, required double size, bool circle = false})`：加载/失败/空数据统一显示 `Image.asset('app_icon.ico')`。
- `bool addAudioToPlaylist(Playlist playlist, Audio audio)` 与 `bool removeAudioFromPlaylist(Playlist playlist, String path)`：去重、修改、递增 `playlistRevision` 并持久化由调用方 await。
- `Playlist.latestAudio`：返回 `audios.values.last` 或 null。

- [ ] **Step 1: 写 RED 测试**：断言爱心点击前 `Icon.fill == 0`、点击后 `Icon.fill == 1`、再次点击恢复 0；断言空歌单/无封面封面组件使用 Logo；断言普通歌单添加歌曲后 revision 变化且最新歌曲成为封面来源。
- [ ] **Step 2: 运行 RED**：
  ```powershell
  flutter test --no-pub test/component/now_playing_favorite_button_test.dart test/library/playlist_test.dart test/component/artwork_thumbnail_test.dart
  ```
- [ ] **Step 3: 实现最小代码**：`NowPlayingFavoriteButton` 使用同一 `Symbols.favorite` 并按 liked 设置 `fill`；封面组件复用 `Audio.cover`；歌单列表 leading 使用 `latestAudio?.cover`；普通歌单菜单和详情删除入口统一使用 repository helper。
- [ ] **Step 4: 运行 GREEN**：重复同一组测试，确认图标、revision、封面回退均通过。
- [ ] **Step 5: 提交**：
  ```powershell
  git add lib/component/artwork_thumbnail.dart lib/component/now_playing_favorite_button.dart lib/library/playlist.dart lib/component/audio_tile.dart lib/page/playlists_page.dart lib/page/playlist_detail_page.dart test/component/now_playing_favorite_button_test.dart test/library/playlist_test.dart test/component/artwork_thumbnail_test.dart
  git commit -m "feat: show liked state and playlist artwork"
  ```

### Task 3: 听歌报告封面与横向柱状图

**Files:**
- Modify: `lib/page/listening_report_page.dart`
- Test: `test/page/listening_report_page_test.dart`
- Test: `test/library/listening_report_test.dart`

**Interfaces:**
- `_RankSection` 接收 `ImageProvider` future 映射函数和已有 destination 函数；不改变 `ListeningReport`/Top10 数据模型。
- `_RecentHistorySection` 使用路径到 `Audio` 的映射显示封面，仍只允许展示和导航，不调用播放。

- [ ] **Step 1: 写 RED 测试**：为歌曲/歌手/专辑/最近播放 fixture 提供可注入封面；断言每个区域有 `ArtworkThumbnail`，最高播放次数柱满宽、较小项按比例缩短，Top 10 和最近 20 条限制不变。
- [ ] **Step 2: 运行 RED**：
  ```powershell
  flutter test --no-pub test/page/listening_report_page_test.dart test/library/listening_report_test.dart
  ```
- [ ] **Step 3: 实现最小 UI**：歌曲用路径 metadata，歌手取首个有封面的作品，专辑取首个作品；用 `AnimatedContainer`/`FractionallySizedBox` 绘制按 `playCount / maxPlayCount` 归一化的横向柱；无 metadata 或 cover 读取失败回退 Logo。
- [ ] **Step 4: 运行 GREEN**：重复两文件测试，确认周期切换、空状态、点击导航和封面回退不回归。
- [ ] **Step 5: 提交**：
  ```powershell
  git add lib/page/listening_report_page.dart test/page/listening_report_page_test.dart test/library/listening_report_test.dart
  git commit -m "feat: add artwork and bar charts to listening reports"
  ```

### Task 4: 搜索异步渐进结果与查询预编译

**Files:**
- Create: `lib/page/search_page/local_search_controller.dart`
- Modify: `lib/library/lyric_search_normalizer.dart`
- Modify: `lib/library/lyric_search_models.dart`
- Modify: `lib/page/search_page/search_page.dart`
- Modify: `lib/page/search_page/search_result_page.dart`
- Test: `test/library/lyric_search_normalizer_test.dart`
- Test: `test/library/lyric_search_models_test.dart`
- Test: `test/page/search_result_page_test.dart`

**Interfaces:**
- `CompiledLyricQuery.compile(String query)` 生成繁体、简体、拼音和紧凑拼音 forms，并提供 `matches(Iterable<String>)`。
- `LocalSearchController.search(String query)` 返回/发布 `LocalSearchState(result, isLoading, isComplete, error)`；内部用 generation token 取消旧任务。

- [ ] **Step 1: 写 RED 测试**：断言 query forms 只编译一次仍保持繁简/拼音匹配；结果页首帧显示 loading；下一轮 pump 出现部分结果；连续 Enter 只保留最后查询；歌词索引同步期间不重复启动整库搜索。
- [ ] **Step 2: 运行 RED**：
  ```powershell
  flutter test --no-pub test/library/lyric_search_normalizer_test.dart test/library/lyric_search_models_test.dart test/page/search_result_page_test.dart
  ```
- [ ] **Step 3: 实现最小控制器**：页面初始化先发布空结果和 loading，再按歌曲/艺术家/专辑/歌词批次扫描；每批 `await Future<void>.delayed(Duration.zero)` 后发布；歌词索引 listener 只在同步完成边界触发一次；TextField suffix 显示 CircularProgressIndicator。
- [ ] **Step 4: 运行 GREEN**：重复三文件测试，确认 Enter 仍只搜索本地内容、歌词结果不触发播放、旧任务不会覆盖新结果。
- [ ] **Step 5: 提交**：
  ```powershell
  git add lib/page/search_page lib/library/lyric_search_normalizer.dart lib/library/lyric_search_models.dart test/library/lyric_search_normalizer_test.dart test/library/lyric_search_models_test.dart test/page/search_result_page_test.dart
  git commit -m "fix: make local search incremental and cancellable"
  ```

### Task 5: 启动只加载与手动完整扫描

**Files:**
- Modify: `lib/library/audio_library.dart`
- Modify: `lib/library/library_update_coordinator.dart`
- Modify: `lib/library/lyric_search_index.dart`
- Modify: `lib/page/updating_page.dart`
- Modify: `lib/page/settings_page/other_settings.dart`
- Modify: `lib/page/welcoming_page.dart`
- Modify: `rust/src/api/tag_reader.rs`
- Modify if generated ABI is removed: `lib/src/rust/api/tag_reader.dart`, `lib/src/rust/frb_generated.dart`, `rust/src/frb_generated.rs`
- Test: `test/library/library_update_coordinator_test.dart`
- Test: `test/page/updating_page_test.dart`
- Test: `test/library/audio_library_test.dart`
- Test: `test/library/lyric_search_index_test.dart`

**Interfaces:**
- `AudioLibrary.scanRoots`：从 index 顶层 `roots` 读取；旧 index 无 roots 时为空且仍可播放。
- `LyricSearchIndex.load()`：只加载现有索引；新增 `Future<void> syncCurrentLibrary()` 供手动/首次完整扫描使用。
- `LibraryUpdateCoordinator.update()`：只用于首次建库和手动完整扫描，顺序固定为 `scan → reload → reconcile → lyric sync`，scan 失败时后续步骤不执行。

- [ ] **Step 1: 写 RED 测试**：增加已有索引启动不调用 scan/reconcile、损坏索引进入错误态、手动 full scan 成功顺序、scan 失败保留旧数据、旧 index 无 roots 禁用扫描、歌词 `load()` 不触发 fingerprint 的测试。
- [ ] **Step 2: 运行 RED**：
  ```powershell
  flutter test --no-pub test/library/library_update_coordinator_test.dart test/page/updating_page_test.dart test/library/audio_library_test.dart test/library/lyric_search_index_test.dart
  ```
- [ ] **Step 3: 实现 Dart 流程**：启动页只 reload index、读歌单/歌词源、load lyric index、load history；文件夹管理的“立即扫描”和首次建库共用 `buildIndexFromFoldersRecursively(folders: scanRoots, indexPath: ...)`；成功后才 reconcile 歌单/历史并 `await syncCurrentLibrary()`；旧 roots 缺失时显示重新选择文件夹提示。
- [ ] **Step 4: 删除 Rust 新增增量实现**：恢复完整建库代码的原子写入和 roots 保存，移除 `FileFingerprint`、path diff、roots 猜测和增量专用测试。若 FRB 生成工具可用，移除 `update_index` ABI；否则保留兼容 wrapper 但其唯一实现必须调用手动完整建库，且 Dart 不得在启动调用它。运行 `rg "build_incremental_index|FileFingerprint|scan_audio_paths|configured_roots_from_index" rust lib`，预期无生产引用。
- [ ] **Step 5: 运行 GREEN**：
  ```powershell
  flutter test --no-pub test/library/library_update_coordinator_test.dart test/page/updating_page_test.dart test/library/audio_library_test.dart test/library/lyric_search_index_test.dart
  dart analyze lib/page/updating_page.dart lib/page/settings_page/other_settings.dart lib/library/audio_library.dart lib/library/lyric_search_index.dart
  ```
- [ ] **Step 6: 提交**：
  ```powershell
  git add lib/library lib/page/updating_page.dart lib/page/settings_page/other_settings.dart lib/page/welcoming_page.dart rust/src/api/tag_reader.rs lib/src/rust test/library test/page/updating_page_test.dart
  git commit -m "fix: make library scanning manual and startup lightweight"
  ```

### Task 6: 文档、集成回归和发布准备

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-11-player-performance-library-ux-design.md` only if implementation decisions materially change
- Test: all affected tests from Tasks 1–5

- [ ] **Step 1: 更新 README**：说明启动不扫描、首次建库和手动完整扫描入口；说明旧 `playback_queue.json` 不再读取、播放队列不跨重启恢复；保留听歌历史和报告数据位置说明。
- [ ] **Step 2: 运行必要集合**：
  ```powershell
  flutter test --no-pub test/component/now_playing_favorite_button_test.dart test/component/artwork_thumbnail_test.dart test/library/playlist_test.dart test/page/listening_report_page_test.dart test/library/listening_report_test.dart test/page/search_result_page_test.dart test/library/lyric_search_normalizer_test.dart test/play_service/playback_history_service_test.dart test/library/library_update_coordinator_test.dart test/page/updating_page_test.dart
  ```
- [ ] **Step 3: 运行一次完整验证**：
  ```powershell
  flutter test --no-pub
  dart analyze lib test
  dart format --output=none --set-exit-if-changed lib test
  git diff --check
  ```
  预期：Flutter 测试无失败，analyze 无 error/warning；允许记录既有 info；Cargo 不在本机安装状态，Rust 由 CI 检查。
- [ ] **Step 4: 检查差异并提交文档**：确认生产代码不再读取 `playback_queue.json`，启动路径无 Rust scan 调用，工作树无生成文件噪声。
- [ ] **Step 5: 提交**：
  ```powershell
  git add README.md
  git commit -m "docs: explain manual scanning and restored playback behavior"
  ```

### Task 7: GitHub CI 与 Release

- [ ] **Step 1: 推送当前分支**：`git push origin agent/fix-ttml-real-world`。
- [ ] **Step 2: 读取 `pubspec.yaml` 版本并创建匹配的 `v*-kalin.*` 标签**；标签版本必须与 pubspec 完全一致。
- [ ] **Step 3: 使用 `gh run list --workflow release.yml --repo Kalincc/coriander_player` 等待唯一 Release 工作流完成，不重复触发。
- [ ] **Step 4: 失败时只读取对应失败步骤日志；成功后核对 Release 页面包含 Portable ZIP、Setup EXE 和 SHA256SUMS.txt。

