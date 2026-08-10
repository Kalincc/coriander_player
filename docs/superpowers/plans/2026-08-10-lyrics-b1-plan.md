# 歌词核心增强 B1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改写音频文件、不新增在线歌词来源的前提下，增强 Coriander Player 的本地歌词搜索和显示同步：支持简体、繁体、完整拼音及翻译文本搜索；提供全局歌词偏移；提供统一的翻译显示开关；保持当前歌词来源选择、搜索结果不自动播放，以及现有 LRC/KRC/QRC/TTML 解析行为。

**Architecture:** 将搜索文本标准化做成纯函数层，由歌词索引建立和查询共同使用；将索引格式升级到 v2，`LyricSearchLine` 保存原文、翻译和预计算搜索形式。将歌词偏移封装为只读时间辅助层，所有歌词视图、`LyricService`、逐字高亮和桌面歌词都使用同一套时间计算，不修改 `LyricLine.start`、逐字时间或音频文件。把偏移与翻译开关放入可通知的 `NowPlayingPagePreference`，控制器负责交互、持久化和刷新当前行，渲染层只消费共享设置。

**Tech Stack:** Flutter/Dart 3.1.4+、现有 `pinyin` 3.3.0、`ChineseHelper`、现有 LRC/TTML/KRC/QRC 歌词模型、JSON 偏好设置、Flutter 定向测试。

## Global Constraints

- 仅搜索本地歌词索引；不新增在线搜索、下载、缓存、编辑、校准或写回标签功能。
- 搜索支持原文、简繁转换、完整拼音（含有空格和无空格形式），不实现拼音首字母搜索。
- 搜索结果继续显示原始歌曲信息和命中歌词片段，不自动播放歌曲；现有 Enter 进入结果的行为保持不变。
- 偏移是全局显示设置，范围 `-10000ms..+10000ms`、步长 `100ms`、默认 `0ms`；正值表示歌词延后，负值表示歌词提前。偏移不改变搜索结果时间戳和音频文件。
- 翻译开关默认开启；没有翻译的歌词不显示无效开关。开关同时影响纵向歌词、横向/迷你歌词、桌面歌词和歌词来源预览。
- 保持现有本地/在线优先级、逐曲指定歌词来源和 `useLocalLyric`/`useOnlineLyric`/`useSpecificLyric` 行为。
- 索引格式升到 v2；旧索引或损坏索引清空后沿用现有后台同步流程重建，不删除音频、歌单或歌词来源配置。
- 每个音频文件的歌词读取失败只影响该文件；不能因为单个文件失败而中止整次索引同步。
- 本计划只安排必要的定向测试和一次最终回归，不重复执行与本功能无关的完整审查。

---

## 文件地图

### 新建文件

- `lib/library/lyric_search_normalizer.dart`：原文、简繁、完整拼音和查询匹配的纯函数。
- `lib/lyric/lyric_timing.dart`：偏移限制、歌词时间线位置、显示起点和逐字高亮进度。
- `lib/lyric/lyric_presentation.dart`：从 LRC/逐字歌词提取主歌词和翻译的统一展示函数。
- `test/library/lyric_search_normalizer_test.dart`：搜索标准化和匹配规则。
- `test/lyric/lyric_timing_test.dart`：偏移、行切换、逐字进度和点击定位规则。
- `test/lyric/lyric_presentation_test.dart`：LRC/逐字歌词翻译展示规则。
- `test/app_preference_test.dart`：新偏好字段的默认值、序列化和旧配置兼容。

### 修改文件

- `lib/library/lyric_search_models.dart`：增加翻译和搜索形式字段，查询改用标准化形式。
- `lib/library/lyric_search_index.dart`：提取翻译、写入索引 v2、兼容旧索引重建。
- `lib/app_preference.dart`：增加 `lyricOffsetMs` 和 `showTranslation`，使歌词设置可通知。
- `lib/play_service/lyric_service.dart`：统一使用偏移后的歌词时间，并在偏好变化时重新发出当前行。
- `lib/play_service/desktop_lyric_service.dart`：使用统一展示函数发送可选翻译。
- `lib/page/now_playing_page/component/lyric_view_controls.dart`：增加偏移加减/重置和翻译开关。
- `lib/page/now_playing_page/component/lyric_view_tile.dart`：按开关展示翻译，逐字高亮使用偏移后的时间。
- `lib/page/now_playing_page/component/vertical_lyric_view.dart`：当前行初始化、点击定位和间奏进度使用统一时间。
- `lib/component/horizontal_lyric_view.dart`：使用统一展示函数，并监听翻译设置。
- `lib/page/now_playing_page/component/lyric_source_view.dart`：来源预览使用偏移和翻译开关。
- `test/library/lyric_search_models_test.dart`：模型 JSON 和多语言查询断言。
- `test/library/lyric_search_index_test.dart`：索引 v2、翻译提取和旧索引重建断言。
- `test/component/lyric_search_result_tile_test.dart`、`test/page/search_result_page_test.dart`：保持原文片段、歌曲信息和“不自动播放”回归断言。
- `test/page/now_playing_page/lyric_scroll_positioner_test.dart`：保留现有居中行为并补充偏移后的当前行刷新覆盖。

## Task 1：建立歌词搜索标准化层

### 1.1 先写失败测试

- [ ] 新建 `test/library/lyric_search_normalizer_test.dart`，覆盖以下行为：
  - `lyricSearchFormsFor('愛情訊息')` 包含原文小写形式、`爱情讯息`、完整拼音 `aiqingxunxi` 和带空格的 `ai qing xun xi`。
  - `lyricSearchMatches('爱情讯息', formsOfTraditionalText)` 与反向查询均为 `true`。
  - 查询 `AI QING` 可以命中拼音，查询 `aq` 为 `false`，证明没有首字母形式。
  - 空白查询返回 `false`；重复形式被去重；拉丁字母查询大小写不敏感。
  - 标准化只改变匹配形式，不改变稍后用于界面展示的原始 `text`。
- [ ] 运行
  ~~~
  flutter test test/library/lyric_search_normalizer_test.dart
  ~~~
  预期：测试先因 `lib/library/lyric_search_normalizer.dart` 不存在或函数未实现而失败。

### 1.2 实现纯函数接口

- [ ] 新建 `lib/library/lyric_search_normalizer.dart`，导出以下稳定接口：
  ~~~
  List<String> lyricSearchFormsFor(String text);

  bool lyricSearchMatches(
    String query,
    Iterable<String> indexedForms,
  );
  ~~~
- [ ] 在 `lyricSearchFormsFor` 中按固定顺序生成去重后的非空形式：
  1. 原文 `trim`、小写、空白归一化后的形式；
  2. `ChineseHelper.convertToSimplifiedChinese` 之后的简体形式；
  3. 简体文本通过 `PinyinHelper.getPinyin(..., separator: ' ')` 得到的带空格完整拼音；
  4. 去掉拼音空格后的完整拼音。
- [ ] 查询端使用同一函数生成查询形式，逐个对索引形式执行 `contains`；不要生成或保存首字母形式。
- [ ] 运行同一个测试命令，预期全部通过。
- [ ] 提交：`feat: add normalized lyric search forms`。

## Task 2：升级歌词搜索模型和索引到 v2

### 2.1 先写模型和索引失败测试

- [ ] 修改 `test/library/lyric_search_models_test.dart`：构造带 `translation` 的 `LyricSearchLine`，断言 JSON 包含 `startMs`、原始 `text`、`translation` 和 `searchForms`，反序列化后列表相等；缺少新字段时仍能从旧形状构造并现场计算搜索形式。
- [ ] 修改 `test/library/lyric_search_index_test.dart`：
  - 用繁体主歌词、简体查询、完整拼音查询和翻译查询分别调用 `searchLyricEntries`，均返回同一歌曲和同一原始歌词行。
  - 用 LRC 的 `主句┃翻译` 和 `SyncLyricLine.translation` 调用 `lyricSearchLinesFromLyric`，断言主文本、翻译和起始时间正确。
  - 写入 v1 envelope 后调用 `load` 再 `sync`，断言写出的 JSON `version == 2`，新行包含搜索形式；索引同步仍继续处理其他文件。
- [ ] 运行
  ~~~
  flutter test test/library/lyric_search_models_test.dart test/library/lyric_search_index_test.dart
  ~~~
  预期：先因缺少字段、版本或匹配逻辑而失败。

### 2.2 修改 `LyricSearchLine` 数据模型

- [ ] 在 `lib/library/lyric_search_models.dart` 保留 `startMs`、`text`，增加可选 `String? translation` 和可选的持久化搜索形式；保留现有两参数构造调用的兼容性。
- [ ] 提供 `List<String> get searchForms`：如果 JSON 有预计算形式则使用它，否则对 `text` 和 `translation` 分别调用 `lyricSearchFormsFor` 并去重。`normalizedText` 可以保留为兼容 getter，但查询不得再只依赖它。
- [ ] `toJson` 写入 `searchForms`，仅在翻译非空时写入 `translation`；`fromJson` 对缺少字段使用兼容默认值。
- [ ] `==` 与 `hashCode` 纳入翻译和搜索形式，保证索引 round-trip 测试有确定结果。

### 2.3 修改歌词提取和查询

- [ ] 在 `lyricSearchLinesFromLyric` 中：
  - `LrcLine` 按第一个 `┃` 拆出主句，剩余部分以 `┃` 连接为可选翻译；保留原始主句用于搜索结果显示。
  - `SyncLyricLine` 使用 `content` 和 `translation`。
  - 过滤主文本为空的行，保留原始 `start.inMilliseconds`。
- [ ] 将 `LyricSearchIndex.formatVersion` 改为 `2`；旧版本、缺字段或损坏 JSON 继续清空内存条目并记录错误，`refreshCurrentLibrary()` 之后沿用现有 `sync` 重建流程。
- [ ] 将 `searchLyricEntries` 改为调用 `lyricSearchMatches`，返回的 `LyricSearchMatch.lines` 仍按原始开始时间排序，不把偏移应用到搜索结果。
- [ ] 运行 Task 2 的测试命令，预期全部通过。
- [ ] 提交：`feat: support multilingual lyric search`。

## Task 3：增加偏好设置、统一歌词时间和展示转换

### 3.1 先写失败测试

- [ ] 新建 `test/lyric/lyric_timing_test.dart`，覆盖：
  - `clampLyricOffsetMs` 将超出范围的值限制到 `-10000..10000`。
  - `lyricClockPosition(5s, +1s) == 4s`，`lyricClockPosition(5s, -1s) == 6s`。
  - `lyricDisplayStart(4s, +1s) == 5s`，负值结果不小于 `0s`。
  - 逐字进度在偏移后仍限制在 `0..1`，零长度单词不产生除零错误。
  - 现有歌词行在 `+1000ms` 时比零偏移晚一秒成为当前行；点击定位目标为原始起点加偏移。
- [ ] 新建 `test/lyric/lyric_presentation_test.dart`，断言 LRC 和逐字歌词在 `showTranslation: true/false` 下分别返回主文本、翻译或 `null`，没有翻译时始终为 `null`。
- [ ] 新建 `test/app_preference_test.dart`，断言：
  - 新对象默认 `lyricOffsetMs == 0`、`showTranslation == true`。
  - `toMap`/`fromMap` round-trip 保留新字段。
  - 缺少新字段的旧 map 使用默认值，不抛异常。
  - 偏移 setter 触发一次 listener，超过范围时保存被限制后的值。

### 3.2 实现时间和展示辅助层

- [ ] 新建 `lib/lyric/lyric_timing.dart`，导出：
  ~~~
  const int lyricOffsetLimitMs = 10000;
  const int lyricOffsetStepMs = 100;

  int clampLyricOffsetMs(int value);
  Duration lyricClockPosition(Duration audioPosition, Duration offset);
  Duration lyricDisplayStart(Duration originalStart, Duration offset);
  double lyricWordProgress({
    required Duration audioPosition,
    required Duration wordStart,
    required Duration wordLength,
    required Duration offset,
  });
  ~~~
- [ ] 新建 `lib/lyric/lyric_presentation.dart`，导出：
  ~~~
  @immutable
  class LyricPresentation {
    final String primary;
    final String? translation;
    const LyricPresentation(this.primary, this.translation);
  }

  LyricPresentation presentLyricLine(
    LyricLine line, {
    required bool showTranslation,
  });

  bool lyricHasTranslation(Lyric lyric);
  ~~~
  LRC 取第一个 `┃` 为主句、其余部分合并为翻译；逐字歌词直接使用 `translation`；关闭开关时只将展示翻译置为 `null`。

### 3.3 扩展偏好设置

- [ ] 将 `NowPlayingPagePreference` 改为 `ChangeNotifier`，增加：
  ~~~
  int lyricOffsetMs = 0;
  bool showTranslation = true;
  ~~~
  构造函数的新参数使用默认值，保证现有四参数调用不变。
- [ ] `toMap` 写入 `"lyricOffsetMs"` 和 `"showTranslation"`；`fromMap` 对缺失、`num` 类型偏移和非 bool 值使用安全默认值。
- [ ] 增加 `setLyricOffsetMs(int)`、`setShowTranslation(bool)`：前者先 clamp，值变化后 `notifyListeners()`；不在模型层写入音频文件。
- [ ] 运行
  ~~~
  flutter test test/lyric/lyric_timing_test.dart test/lyric/lyric_presentation_test.dart test/app_preference_test.dart
  ~~~
  预期全部通过。
- [ ] 提交：`feat: add lyric display preferences and timing helpers`。

## Task 4：把偏移接入播放服务和主界面歌词时间计算

### 4.1 先补充服务边界测试

- [ ] 在 `test/lyric/lyric_timing_test.dart` 增加对正负偏移、零偏移和重置的行索引/点击定位断言；用纯 `LyricLine` 列表测试，不启动真实音频设备。
- [ ] 在 `test/page/now_playing_page/lyric_scroll_positioner_test.dart` 保留现有居中断言，并增加“偏好变化后服务重新发出当前行”的最小事件断言；测试使用已有 fake/fixture，不创建真实桌面歌词进程。

### 4.2 修改 `LyricService`

- [ ] 在 `lib/play_service/lyric_service.dart` 增加只读偏移 getter，并将位置流判断统一改为比较 `lyricClockPosition(audioPosition, offset)` 与原始 `line.start`。
- [ ] 抽取 `_emitLyricLine(int index, Lyric lyric)`：先向 `_lyricLineStreamController` 发出索引，再在桌面歌词可用时发送同一行，避免位置流和偏好变化各自复制逻辑。
- [ ] `findCurrLyricLine()` 使用同一时间线重新计算 `_nextLyricLine`；新增 `refreshCurrentLyric()` 或等价入口，在偏好变化时立即发出当前行并刷新桌面歌词。
- [ ] 构造时监听 `AppPreference.instance.nowPlayingPagePref`；偏移或翻译开关变化时调用刷新入口；`dispose` 时移除 listener。
- [ ] `updateLyric`、`useLocalLyric`、`useOnlineLyric`、`useSpecificLyric` 载入歌词后都调用统一的当前行计算，保留现有来源选择和异步行为。

### 4.3 修改主界面和横向视图

- [ ] 在 `lib/page/now_playing_page/component/vertical_lyric_view.dart`：
  - `_initLyricView` 使用 `lyricClockPosition` 计算初始当前行。
  - `_seekToLyricLine` seek 到 `lyricDisplayStart(line.start, offset)`，再让 `LyricService` 计算当前行。
  - `LyricTransitionTileController` 的进度使用同一偏移辅助函数。
- [ ] 在 `lib/page/now_playing_page/component/lyric_view_tile.dart`：逐字高亮调用 `lyricWordProgress`，不直接用原始 `position - word.start`；所有翻译渲染改用 `presentLyricLine` 和控制器的开关。
- [ ] 在 `lib/component/horizontal_lyric_view.dart`：保留现有横向滚动时长，当前文本改用统一展示函数，并监听 `NowPlayingPagePreference` 以便切换翻译后立即刷新。
- [ ] 运行
  ~~~
  flutter test test/lyric/lyric_timing_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
  ~~~
  预期全部通过；不得出现音频设备初始化或桌面进程启动错误。
- [ ] 提交：`feat: apply lyric offset across playback views`。

## Task 5：增加歌词控制项并统一翻译显示

### 5.1 先写控制器测试

- [ ] 在 `test/app_preference_test.dart` 或新建 `test/component/lyric_view_controls_test.dart`，直接实例化 `LyricViewController`，断言：
  - 增加/减少每次变化 `100ms`，到边界后不越界。
  - 重置回 `0ms`。
  - 切换翻译后 `showTranslation` 反转，并通知监听者。
  - 控制器调用只更新偏好和内存显示设置，不触碰音频文件路径。
- [ ] 使用 `flutter test` 运行该测试，预期先因控制器方法或状态不存在而失败。

### 5.2 实现控制器和菜单

- [ ] 在 `lib/page/now_playing_page/component/lyric_view_controls.dart` 为 `LyricViewController` 增加 `lyricOffsetMs`、`showTranslation` getter，以及 `increaseLyricOffset`、`decreaseLyricOffset`、`resetLyricOffset`、`toggleTranslation` 方法；每次变更调用偏好 setter、`unawaited(AppPreference.instance.save())` 和必要的歌词刷新。
- [ ] 在 `LyricViewControls` 现有来源按钮、对齐按钮和字号按钮旁增加偏移菜单：减小、显示当前值、增大、重置；范围边界按钮禁用，当前值显示为带符号的毫秒或秒。
- [ ] 增加翻译显示/隐藏按钮；通过当前歌词 future 判断 `lyricHasTranslation`，无翻译时返回 `SizedBox.shrink()`，不显示无效控制。
- [ ] 控件 tooltip 和状态全部使用中文，沿用现有 Material Symbols 和主题色。

### 5.3 接入来源预览和桌面歌词

- [ ] 在 `lib/page/now_playing_page/component/lyric_source_view.dart` 使用 `lyricClockPosition` 找当前预览行，并用 `presentLyricLine` 构造 subtitle；全局关闭翻译后预览只显示主歌词。
- [ ] 在 `lib/play_service/desktop_lyric_service.dart` 的 `sendLyricLineMessage` 中使用 `presentLyricLine`，不再直接拆分和发送隐藏的翻译；保留原有消息类型和时长。
- [ ] 确认 `LyricService` 的偏好 listener 会在切换翻译后重新发送当前桌面歌词，因此不需要修改 `desktop_lyric` 子项目。
- [ ] 运行
  ~~~
  flutter test test/lyric/lyric_presentation_test.dart test/app_preference_test.dart test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart
  ~~~
  预期全部通过，搜索结果仍显示原始歌词片段且不会触发播放。
- [ ] 提交：`feat: add lyric translation display toggle`。

## Task 6：定向回归和完成前验证

- [ ] 更新 `test/library/lyric_search_models_test.dart`、`test/library/lyric_search_index_test.dart`、`test/component/lyric_search_result_tile_test.dart` 和 `test/page/search_result_page_test.dart`，确保 Enter/点击只定位结果、不自动播放，且命中翻译时仍显示对应歌曲信息和原始歌词片段。
- [ ] 执行 Dart 格式检查：
  ~~~
  dart format --output=none --set-exit-if-changed lib/app_preference.dart lib/library/lyric_search_normalizer.dart lib/library/lyric_search_models.dart lib/library/lyric_search_index.dart lib/lyric/lyric_timing.dart lib/lyric/lyric_presentation.dart lib/play_service/lyric_service.dart lib/play_service/desktop_lyric_service.dart lib/page/now_playing_page/component/lyric_view_controls.dart lib/page/now_playing_page/component/lyric_view_tile.dart lib/page/now_playing_page/component/vertical_lyric_view.dart lib/component/horizontal_lyric_view.dart lib/page/now_playing_page/component/lyric_source_view.dart test/library/lyric_search_normalizer_test.dart test/library/lyric_search_models_test.dart test/library/lyric_search_index_test.dart test/lyric/lyric_timing_test.dart test/lyric/lyric_presentation_test.dart test/app_preference_test.dart
  ~~~
  预期：命令退出码为 `0`，没有格式变化。
- [ ] 执行必要的定向回归（包含现有歌词解析测试，不执行与本功能无关的全量测试）：
  ~~~
  flutter test test/library test/lyric test/component/lyric_search_result_tile_test.dart test/page/search_result_page_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
  ~~~
  预期：现有 LRC、TTML 及仓库中已有的 KRC/QRC 歌词测试与新增 B1 测试全部通过。
- [ ] 执行改动范围分析：
  ~~~
  flutter analyze lib/app_preference.dart lib/library lib/lyric lib/play_service lib/page/now_playing_page/component/lyric_view_controls.dart lib/page/now_playing_page/component/lyric_view_tile.dart lib/page/now_playing_page/component/vertical_lyric_view.dart lib/component/horizontal_lyric_view.dart test
  ~~~
  预期：无 error；已有 warning 需确认不是本次改动引入。
- [ ] 执行 `git diff --check`，预期无空白错误；检查改动中不存在对音频、歌词标签、在线缓存文件的写操作。
- [ ] 手工验收 8 项：繁体歌词可用简体搜索、简体歌词可用繁体搜索、完整拼音搜索、翻译命中、搜索不自动播放、`+1000ms` 延后约一秒、隐藏翻译覆盖所有视图、现有来源选择和 LRC/TTML/KRC/QRC 解析不回归。
- [ ] 完成后仅提交必要的实现提交；不在本计划中创建 release、推送或修改远程分支，待用户确认集成方式后再执行。
