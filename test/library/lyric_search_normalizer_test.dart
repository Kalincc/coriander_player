import 'package:coriander_player/library/lyric_search_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates normalized Chinese and complete pinyin search forms', () {
    final forms = lyricSearchFormsFor('愛情訊息');

    expect(
      forms,
      containsAllInOrder([
        '愛情訊息',
        '爱情讯息',
        'ai qing xun xi',
        'aiqingxunxi',
      ]),
    );
  });

  test('matches Traditional and Simplified Chinese in either query direction',
      () {
    final traditionalForms = lyricSearchFormsFor('愛情訊息');
    final simplifiedForms = lyricSearchFormsFor('爱情讯息');

    expect(lyricSearchMatches('爱情讯息', traditionalForms), isTrue);
    expect(lyricSearchMatches('愛情訊息', simplifiedForms), isTrue);
  });

  test('matches complete pinyin case-insensitively but not initials', () {
    final forms = lyricSearchFormsFor('愛情訊息');

    expect(lyricSearchMatches('AI QING', forms), isTrue);
    expect(lyricSearchMatches('aq', forms), isFalse);
  });

  test('rejects blank queries and de-duplicates normalized forms', () {
    expect(lyricSearchMatches('  \t\n ', lyricSearchFormsFor('爱情讯息')), isFalse);

    final forms = lyricSearchFormsFor('爱情讯息');

    expect(forms.toSet(), hasLength(forms.length));
    expect(forms.where((form) => form == '爱情讯息'), hasLength(1));
  });

  test('normalizes Latin queries case-insensitively', () {
    final forms = lyricSearchFormsFor('Love Song');

    expect(lyricSearchMatches('LOVE', forms), isTrue);
  });

  test('leaves the display text unchanged while deriving search forms', () {
    const text = '  愛情訊息  ';

    lyricSearchFormsFor(text);

    expect(text, '  愛情訊息  ');
  });
}
