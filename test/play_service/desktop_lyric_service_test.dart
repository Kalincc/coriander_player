import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/play_service/desktop_lyric_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop lyric message hides translation without changing duration', () {
    final line = LrcLine(
      Duration.zero,
      'primary┃translation┃continued',
      isBlank: false,
      length: const Duration(seconds: 3),
    );

    final shown = desktopLyricLineMessage(line, showTranslation: true)!;
    final hidden = desktopLyricLineMessage(line, showTranslation: false)!;

    expect(shown.content, 'primary');
    expect(shown.translation, 'translation┃continued');
    expect(shown.length, const Duration(seconds: 3));
    expect(hidden.content, 'primary');
    expect(hidden.translation, isNull);
    expect(hidden.length, const Duration(seconds: 3));
  });
}
