# TTML 与 LRC 本地歌词支持实施计划

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ] syntax) for tracking.

**Goal:** 让播放器同时解析现有 LRC 和 FLAC/MP4 等标签中常见的 Apple/iTunes TTML 逐行、逐字歌词，并让两者都能播放显示和参与本地歌词搜索。

**Architecture:** 保留 Rust 标签读取层，只把原始歌词字符串交给 Dart。Lrc 层增加统一格式判断：TTML 交给独立解析器，其他文本继续走现有 LRC 解析器；TTML 结果复用 LrcSource.local 语义和现有 SyncLyricLine/SyncLyricWord UI。歌词搜索索引从只收集无同步行改为收集所有有文本的歌词行。

**Tech Stack:** Flutter/Dart 3.1.4+、xml Dart 包、现有 Lyric/Lrc/SyncLyricLine 模型、Flutter Test、现有 Rust FFI 标签读取。

## Global Constraints

- 目标平台是 Windows 版 Coriander Player；不修改 desktop_lyric。
- 不加入 QRC、KRC、ID3 SYLT 或纯文本歌词格式。
- 不修改音频文件、Mp3tag 标签、在线歌词来源或下载逻辑。
- Rust get_lyric_from_path 继续返回原始歌词字符串；本次格式识别在 Dart 完成。
- 现有 LRC、同名外挂 .lrc、offset、多时间戳行和本地歌词搜索行为必须保持兼容。
- TTML 解析错误按单首歌曲隔离，不能阻塞音乐库、播放或歌词索引。
- 实现完成前不合并到 fork main，也不构建新的 Release。

---

## 文件地图

- Create: lib/lyric/ttml.dart — TTML 文档、时间属性、p/span 到同步歌词模型的解析。
- Modify: lib/lyric/lrc.dart — 统一格式入口和音频路径读取调用；保留现有 LRC 算法。
- Modify: lib/library/lyric_search_index.dart — 将同步歌词行转换为可搜索的整行文本。
- Modify: pubspec.yaml — 声明直接使用的 xml 依赖。
- Create: test/lyric/ttml_test.dart — TTML 行级、字级、时间格式和异常输入测试。
- Create: test/lyric/lrc_parser_test.dart — 统一入口的格式选择和 LRC 回归测试。
- Modify: test/library/lyric_search_index_test.dart — TTML 同步行进入搜索索引的测试。

## Task 1: 添加 TTML 模型、解析器和单元测试

**Files:**
- Create: lib/lyric/ttml.dart
- Modify: pubspec.yaml
- Create: test/lyric/ttml_test.dart

**Interfaces:**
- Produces class Ttml extends Lrc with Ttml(List<LyricLine> lines) and static Ttml? fromTtmlText(String text).
- Produces class TtmlLine extends SyncLyricLine and class TtmlWord extends SyncLyricWord.
- Ttml always uses LrcSource.local, so existing local-source controls continue to work.

- [ ] Step 1: Write failing TTML parser tests

Add a compact fixture containing a word-timed line and a line-timed paragraph:

~~~dart
const wordTimedTtml = '''
<tt xmlns="http://www.w3.org/ns/ttml"
    xmlns:itunes="http://music.apple.com/lyric-ttml-internal"
    itunes:timing="Word">
  <body><div>
    <p begin="19.311" end="22.288">
      <span begin="19.311" end="19.720">用</span>
      <span begin="19.720" end="20.491">起伏</span>
      <span begin="20.491" end="21.126">的</span>
    </p>
  </div></body>
</tt>
''';

test('parses TTML word timings into SyncLyricLine', () {
  final lyric = Ttml.fromTtmlText(wordTimedTtml);
  final line = lyric!.lines.single as TtmlLine;

  expect(line.start.inMilliseconds, 19311);
  expect(line.length.inMilliseconds, 2977);
  expect(line.content, '用起伏的');
  expect(line.words.map((word) => word.content), ['用', '起伏', '的']);
  expect(line.words[1].start.inMilliseconds, 19720);
  expect(line.words[1].length.inMilliseconds, 771);
});
~~~

Add tests for a p with no spans, decimal-second timings, hh:mm:ss.mmm, dur, BOM/outer whitespace, malformed XML, missing text, and invalid timing. Every invalid fixture must assert isNull or that invalid nodes are skipped without throwing.

- [ ] Step 2: Run the focused test to confirm the red state

Run:

~~~powershell
flutter test test/lyric/ttml_test.dart
~~~

Expected: FAIL because lib/lyric/ttml.dart and Ttml.fromTtmlText do not exist yet.

- [ ] Step 3: Add the direct XML dependency and implement the minimal parser

Add the locked-compatible direct dependency:

~~~yaml
dependencies:
  xml: ^6.5.0
~~~

Implement Ttml.fromTtmlText with these rules:

~~~dart
final document = XmlDocument.parse(text.trim().replaceFirst('\uFEFF', ''));
if (document.rootElement.localName != 'tt') return null;
final paragraphs = document.descendants.whereType<XmlElement>()
    .where((element) => element.localName == 'p');
~~~

Parse timing values as either decimal seconds (19.311) or clock time (hh:mm:ss.mmm). Resolve end first, then dur; for a word without end, use its dur or the next word start. Create TtmlWord values from visible span text, create a TtmlLine for every paragraph with text and valid start/length, sort lines by start, and return null when no valid line remains. Preserve spaces between visible child text nodes when building content.

- [ ] Step 4: Run the TTML tests and check the exact result

Run:

~~~powershell
flutter test test/lyric/ttml_test.dart
~~~

Expected: all TTML parser tests pass, including the word start/length assertions and malformed-input cases.

- [ ] Step 5: Commit the isolated parser task

~~~powershell
git add pubspec.yaml pubspec.lock lib/lyric/ttml.dart test/lyric/ttml_test.dart
git commit -m "feat: parse embedded TTML lyrics"
~~~

## Task 2: Wire format detection into local audio lyric loading

**Files:**
- Modify: lib/lyric/lrc.dart:1-5, 180-195
- Create: test/lyric/lrc_parser_test.dart

**Interfaces:**
- Produces Lrc? parseLocalLyricText(String text, {String? separator = '┃'}) in lib/lyric/lrc.dart.
- Keeps Future<Lrc?> Lrc.fromAudioPath(Audio belongTo, {String? separator = '┃'}) unchanged for callers; Ttml is returned through the Lrc subtype.

- [ ] Step 1: Write failing format-selection and LRC regression tests

Test both branches through the new function:

~~~dart
test('selects TTML when the XML root is tt', () {
  final lyric = parseLocalLyricText(wordTimedTtml);
  expect(lyric, isA<Ttml>());
  expect(lyric!.lines.single.content, '用起伏的');
});

test('keeps ordinary LRC parsing unchanged', () {
  final lyric = parseLocalLyricText('[00:01.20]first\n[00:02.40]second');
  expect(lyric, isA<Lrc>());
  expect(lyric!.lines.map((line) => line.start.inMilliseconds), [1200, 2400]);
});

test('returns null for malformed XML without throwing', () {
  expect(parseLocalLyricText('<tt><p>broken'), isNull);
});
~~~

- [ ] Step 2: Run the parser integration tests to confirm the red state

~~~powershell
flutter test test/lyric/lrc_parser_test.dart
~~~

Expected: FAIL because parseLocalLyricText is undefined and Lrc.fromAudioPath still sends all text directly to LRC parsing.

- [ ] Step 3: Implement the smallest unified entry point

In lrc.dart, import ttml.dart and implement detection after trimming BOM/whitespace:

~~~dart
Lrc? parseLocalLyricText(String text, {String? separator = '┃'}) {
  final normalized = text.replaceFirst('\uFEFF', '').trim();
  if (normalized.isEmpty) return null;

  if (normalized.startsWith('<')) {
    final ttml = Ttml.fromTtmlText(normalized);
    if (ttml != null) return ttml;
  }
  return Lrc.fromLrcText(normalized, LrcSource.local, separator: separator);
}
~~~

Update Lrc.fromAudioPath so the getLyricFromPath result goes through parseLocalLyricText. Do not change the Rust FFI call or the external .lrc fallback.

- [ ] Step 4: Run focused parser and existing lyric tests

~~~powershell
flutter test test/lyric/lrc_parser_test.dart test/lyric/ttml_test.dart test/component/lyric_search_result_tile_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
~~~

Expected: all tests pass, and ordinary LRC output remains unchanged.

- [ ] Step 5: Commit the loading integration

~~~powershell
git add lib/lyric/lrc.dart test/lyric/lrc_parser_test.dart
git commit -m "feat: detect TTML and LRC local lyrics"
~~~

## Task 3: Include TTML lines in local lyric search

**Files:**
- Modify: lib/library/lyric_search_index.dart:35-48
- Modify: test/library/lyric_search_index_test.dart

**Interfaces:**
- Produces List<LyricSearchLine> lyricSearchLinesFromLyric(Lrc lyric) as the shared conversion used by readLocalLyricLines and tests.
- The helper emits one LyricSearchLine per non-empty UnsyncLyricLine or SyncLyricLine, using line.content and line.start.inMilliseconds.

- [ ] Step 1: Add the failing search conversion test

Construct a Ttml from the fixture and assert its joined line text is searchable:

~~~dart
test('indexes TTML sync lines as searchable full lines', () {
  final lyric = Ttml.fromTtmlText(wordTimedTtml)!;
  final lines = lyricSearchLinesFromLyric(lyric);

  expect(lines, [
    const LyricSearchLine(startMs: 19311, text: '用起伏的'),
  ]);
});
~~~

- [ ] Step 2: Run the index test to confirm the red state

~~~powershell
flutter test test/library/lyric_search_index_test.dart
~~~

Expected: FAIL because the conversion helper does not exist and the current implementation filters out SyncLyricLine.

- [ ] Step 3: Implement the shared line conversion and use it in readLocalLyricLines

Replace the whereType<UnsyncLyricLine>()-only path with an explicit conversion that handles both concrete line types:

~~~dart
List<LyricSearchLine> lyricSearchLinesFromLyric(Lrc lyric) => lyric.lines
    .where((line) => line is UnsyncLyricLine || line is SyncLyricLine)
    .map((line) => LyricSearchLine(
          startMs: line.start.inMilliseconds,
          text: line is UnsyncLyricLine
              ? line.content
              : (line as SyncLyricLine).content,
        ))
    .where((line) => line.text.trim().isNotEmpty)
    .toList(growable: false);
~~~

Keep readLocalLyricLines responsible only for loading the lyric and delegating to this helper. Do not change index JSON, fingerprints, worker limits, or search matching rules.

- [ ] Step 4: Run the index and search regression tests

~~~powershell
flutter test test/library/lyric_search_index_test.dart test/library/lyric_search_models_test.dart test/page/search_result_page_test.dart test/component/lyric_search_result_tile_test.dart
~~~

Expected: the new TTML search assertion and all existing index/search tests pass.

- [ ] Step 5: Commit the search integration

~~~powershell
git add lib/library/lyric_search_index.dart test/library/lyric_search_index_test.dart
git commit -m "feat: index TTML lyric lines for local search"
~~~

## Task 4: Final verification and handoff

**Files:**
- Modify: none unless a verification failure identifies a directly related defect.

- [ ] Step 1: Run the complete focused feature suite

~~~powershell
flutter test test/lyric/ttml_test.dart test/lyric/lrc_parser_test.dart test/library/lyric_search_index_test.dart test/library/lyric_search_models_test.dart test/page/search_result_page_test.dart test/component/lyric_search_result_tile_test.dart test/page/now_playing_page/lyric_scroll_positioner_test.dart
~~~

Expected: all tests pass with zero failures.

- [ ] Step 2: Run targeted analysis on every changed Dart file

~~~powershell
flutter analyze --no-fatal-infos lib/lyric/ttml.dart lib/lyric/lrc.dart lib/library/lyric_search_index.dart test/lyric/ttml_test.dart test/lyric/lrc_parser_test.dart test/library/lyric_search_index_test.dart
~~~

Expected: exit code 0; existing informational diagnostics are acceptable, but no new errors or warnings from these files.

- [ ] Step 3: Run repository-level verification available in the release workflow

~~~powershell
flutter test
flutter analyze --no-fatal-infos lib test
cargo check --manifest-path rust/Cargo.toml
git diff --check
git status --short --branch
~~~

Expected: Flutter tests, analysis, Rust check and whitespace check succeed; the final status shows only intentional committed changes.

- [ ] Step 4: Record the result before any release action

Confirm the branch contains only TTML/LRC implementation, tests and the already committed design/plan documents. Do not push a tag or create a Release in this plan; ask separately after the user reviews the implementation result.

