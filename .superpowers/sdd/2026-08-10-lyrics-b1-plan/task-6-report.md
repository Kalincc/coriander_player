# Task 6 — 定向回归与完成前验证

## 最小测试补充

- 在 `test/page/search_result_page_test.dart` 增加了一个 widget 测试：对搜索框输入关键词并触发 `TextInputAction.done`（Enter）后，仅刷新本地歌词结果。
- 现有 `lyric_search_result_tile_test.dart` 已逐项覆盖歌曲标题、歌词行和定位按钮的点击均只调用 `onLocate`；`SearchResultPage` 的该回调仅执行 `context.push(AUDIOS_PAGE, extra: match.audio)`，没有调用播放服务。因此没有扩大为真实播放器或路由集成测试。
- `lyric_search_index_test.dart` 与 `lyric_search_models_test.dart` 的变动仅为新增 B1 断言的 `const` lint 清理；不改变测试语义。

## 验证命令与结果

1. `dart format --output=none --set-exit-if-changed`（19 个计划文件，加上 2 个搜索页面测试文件）
   - 退出码 `0`，`Formatted 21 files (0 changed)`。
2. `flutter test test/library test/lyric test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart`
   - 退出码 `0`，`81` 项通过、`0` 项失败。
3. 在最后两项 `const` 样式清理后，执行
   `flutter test test/library/lyric_search_models_test.dart test/library/lyric_search_index_test.dart test/page/search_result_page_test.dart`
   - 退出码 `0`，`33` 项通过、`0` 项失败。
4. `flutter analyze lib/app_preference.dart lib/library lib/lyric lib/play_service lib/page/now_playing_page/component/lyric_view_controls.dart lib/page/now_playing_page/component/lyric_view_tile.dart lib/page/now_playing_page/component/vertical_lyric_view.dart lib/component/horizontal_lyric_view.dart test`
   - 退出码 `1`，原因是 Flutter 将 `16` 条既有 info 计入非零结果；无 error 或 warning。内容为命名风格、旧版 `withOpacity`，以及基线已有的桌面歌词颜色 `.value` 提示。没有本任务新增 info，因此不在本次范围内改动。
5. `git diff --check 19d33f5..HEAD` 及 `git diff --check`
   - 均退出码 `0`，没有空白错误。

## 范围与副作用检查

- B1 的改动文件中没有音频文件、歌词标签文件或在线缓存文件；搜索结果页面只定位到音乐库页面，不触发播放。
- `LyricSearchIndex` 保留既有的本地 JSON 索引原子写入流程，以持久化 v2 本地搜索索引；它不写回音频/歌词标签，也不下载或写入在线歌词缓存。
- 已由定向解析测试覆盖现有 LRC、TTML、KRC、QRC 解析路径；本次未执行无关的全量测试。
