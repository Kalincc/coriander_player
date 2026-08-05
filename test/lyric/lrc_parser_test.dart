import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/ttml.dart';
import 'package:flutter_test/flutter_test.dart';

const wordTimedTtml = '''
<tt><body><div><p begin="1" end="2">
  <span begin="1" end="1.5">用</span><span begin="1.5" end="2">起伏的</span>
</p></div></body></tt>
''';

void main() {
  test('selects TTML when the XML root is tt', () {
    final lyric = parseLocalLyricText(wordTimedTtml);

    expect(lyric, isA<Ttml>());
    expect((lyric!.lines.single as TtmlLine).content, '用起伏的');
  });

  test('keeps ordinary LRC parsing unchanged', () {
    final lyric = parseLocalLyricText('[00:01.20]first\n[00:02.40]second');

    expect(lyric, isA<Lrc>());
    expect(lyric!.lines.map((line) => line.start.inMilliseconds), [1200, 2400]);
  });

  test('returns null for malformed XML without throwing', () {
    expect(parseLocalLyricText('<tt><p>broken'), isNull);
  });
}
