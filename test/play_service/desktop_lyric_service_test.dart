import 'dart:convert';

import 'package:desktop_lyric/message.dart' as msg;
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/play_service/desktop_lyric_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('control messages survive merged and split stream chunks', () async {
    final pause = const msg.ControlEventMessage(msg.ControlEvent.pause)
        .buildMessageJson();
    final next = const msg.ControlEventMessage(msg.ControlEvent.nextAudio)
        .buildMessageJson();
    final bytes = utf8.encode('$pause\ninvalid\n$next\n');
    final events = await desktopLyricControlMessages(Stream.fromIterable([
      bytes.sublist(0, 7),
      bytes.sublist(7, 19),
      bytes.sublist(19),
    ])).toList();
    expect(events.map((event) => event.event),
        [msg.ControlEvent.pause, msg.ControlEvent.nextAudio]);
  });

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
