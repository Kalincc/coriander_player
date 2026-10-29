import 'dart:convert';

import 'package:coriander_player/lyric/krc.dart';
import 'package:flutter_test/flutter_test.dart';

const _lines = '[0,1000]<0,1000,0>first\n[1000,1000]<0,1000,0>second';
String _language(List<Object> content) =>
    '[language:${base64Encode(utf8.encode(jsonEncode({'content': content})))}]';

void main() {
  test('keeps original KRC when the language frame contains only pronunciation',
      () {
    final lyric = Krc.fromKrcText('${_language([
          {
            'type': 0,
            'lyricContent': [
              ['pinyin']
            ]
          }
        ])}\n$_lines');
    expect(lyric.lines, hasLength(2));
    expect((lyric.lines.first as KrcLine).translation, isNull);
  });

  test('keeps untranslated lines when translation is shorter than the original',
      () {
    final lyric = Krc.fromKrcText('${_language([
          {
            'type': 1,
            'lyricContent': [
              ['第一行']
            ]
          }
        ])}\n$_lines');
    expect(lyric.lines.cast<KrcLine>().map((line) => line.translation),
        ['第一行', null]);
  });

  test('ignores excess translation lines and empty translation entries', () {
    final lyric = Krc.fromKrcText('${_language([
          {
            'type': 1,
            'lyricContent': [
              [],
              ['第二行'],
              ['多余']
            ]
          }
        ])}\n$_lines');
    expect(lyric.lines.cast<KrcLine>().map((line) => line.translation),
        [null, '第二行']);
  });

  test('optional invalid language metadata and blank lines do not discard text',
      () {
    final lyric = Krc.fromKrcText('\n[language:not-base64]\n$_lines\n');
    expect(lyric.lines, hasLength(2));
    expect((lyric.lines.first as KrcLine).words.single.content, 'first');
  });

  test('metadata containing commas is not treated as a timed lyric', () {
    final lyric = Krc.fromKrcText('[ar:Artist,Guest]\n$_lines');
    expect(lyric.lines, hasLength(2));
  });
}
