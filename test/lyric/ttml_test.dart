import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/ttml.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  test('parses TTML word timings into SyncLyricLine', () {
    final lyric = Ttml.fromTtmlText(wordTimedTtml);
    final line = lyric!.lines.single as TtmlLine;

    expect(line.start.inMilliseconds, 19311);
    expect(line.length.inMilliseconds, 2977);
    expect(line.content, '用起伏的');
    expect(line.words.map((word) => word.content), ['用', '起伏', '的']);
    expect(line.words[1].start.inMilliseconds, 19720);
    expect(line.words[1].length.inMilliseconds, 771);
    expect(lyric.source, LrcSource.local);
  });

  test('parses line-timed paragraph without spans', () {
    final lyric = Ttml.fromTtmlText('''
<tt><body><div><p begin="1.5" end="3.25">line timed text</p></div></body></tt>
''');

    final line = lyric!.lines.single as LrcLine;
    expect(line.start.inMilliseconds, 1500);
    expect(line.length.inMilliseconds, 1750);
    expect(line.content, 'line timed text');
  });

  test('parses Apple minute-second clock timestamps', () {
    final lyric = Ttml.fromTtmlText('''
<tt><body><div>
  <p begin="57.085" end="1:03.351">
    <span begin="57.085" end="58.000">先</span>
    <span begin="58.000" end="1:03.351">後</span>
  </p>
</div></body></tt>
''');

    final line = lyric!.lines.single as TtmlLine;
    expect(line.start.inMilliseconds, 57085);
    expect(line.length.inMilliseconds, 6266);
  });

  test('parses decimal and clock timestamps with dur', () {
    final lyric = Ttml.fromTtmlText('''
<tt><body><div>
  <p begin="00:01:02.500" dur="1.250">clock</p>
  <p begin="3.125" dur="0.875">decimal</p>
</div></body></tt>
''');

    expect(
        lyric!.lines.map((line) => line.start.inMilliseconds), [3125, 62500]);
    expect(lyric.lines.map((line) => (line as LrcLine).length.inMilliseconds),
        [875, 1250]);
  });

  test('uses next word start when a word has no end or dur', () {
    final lyric = Ttml.fromTtmlText('''
<tt><body><div><p begin="1" end="3">
  <span begin="1">A</span><span begin="2" dur="0.5">B</span>
</p></div></body></tt>
''');

    final words = (lyric!.lines.single as TtmlLine).words;
    expect(words[0].length.inMilliseconds, 1000);
    expect(words[1].length.inMilliseconds, 500);
  });

  test('trims outer whitespace and a leading BOM', () {
    final lyric = Ttml.fromTtmlText(
      ' \uFEFF  <tt><body><div><p begin="0" dur="1">trimmed</p></div></body></tt>'
      '  ',
    );

    expect(lyric!.lines.single.start, Duration.zero);
  });

  test('preserves spaces between visible child text nodes', () {
    final lyric = Ttml.fromTtmlText('''
<tt><body><div><p begin="0" dur="1"><span begin="0" dur=".5">hello</span> <span begin=".5" dur=".5">world</span></p></div></body></tt>
''');

    expect((lyric!.lines.single as TtmlLine).content, 'hello world');
  });

  test('returns null for malformed XML or a non-TT root', () {
    expect(Ttml.fromTtmlText('<tt><p begin="0">bad'), isNull);
    expect(
        Ttml.fromTtmlText('<xml><p begin="0" dur="1">bad</p></xml>'), isNull);
  });

  test('skips paragraphs with missing text or invalid timing', () {
    final lyric = Ttml.fromTtmlText('''
<tt><body><div>
  <p begin="0" dur="1"></p>
  <p begin="not-a-time" dur="1">invalid</p>
  <p begin="1" end="0">backwards</p>
  <p begin="2" dur="1">valid</p>
</div></body></tt>
''');

    expect(lyric!.lines, hasLength(1));
    expect((lyric.lines.single as LrcLine).content, 'valid');
  });
}
