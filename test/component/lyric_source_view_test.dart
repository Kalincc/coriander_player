import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/online_lyric_models.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the source preview line using the lyric clock position', () {
    final lyric = Lrc(
      [
        LrcLine(Duration.zero, 'first', isBlank: false),
        LrcLine(const Duration(seconds: 1), 'second', isBlank: false),
      ],
      LrcSource.web,
    );

    final line = lyricSourcePreviewLine(
      lyric,
      const Duration(milliseconds: 1050),
      const Duration(milliseconds: 100),
    );

    expect(line, isA<LrcLine>());
    expect((line as LrcLine).content, 'first');
  });

  test('source preview hides translations through lyric presentation', () {
    final line = LrcLine(
      Duration.zero,
      'primary┃translation┃continued',
      isBlank: false,
    );

    expect(
      lyricSourcePreviewText(line, showTranslation: true),
      '当前：primary┃translation┃continued',
    );
    expect(
      lyricSourcePreviewText(line, showTranslation: false),
      '当前：primary',
    );
  });

  test('match summary contains source, score, and reasons', () {
    final result = SongSearchResult(
      ResultSource.qq,
      '红豆',
      '王菲',
      '唱游',
      .9,
      qqSongId: 1,
      matchReasons: const ['标题一致', '歌手一致'],
    );

    final summary = lyricSourceMatchSummary(result);

    expect(summary, contains('QQ音乐'));
    expect(summary, contains('90%'));
    expect(summary, contains('标题一致'));
    expect(summary, contains('歌手一致'));
  });
}
