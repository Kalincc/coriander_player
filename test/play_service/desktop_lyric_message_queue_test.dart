import 'dart:async';
import 'dart:convert';

import 'package:coriander_player/play_service/desktop_lyric_message_queue.dart';
import 'package:desktop_lyric/message.dart' as msg;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes newline-delimited frames in enqueue order', () async {
    final writes = <String>[];
    final firstRelease = Completer<void>();
    final queue = DesktopLyricMessageQueue((frame) async {
      writes.add(frame);
      if (writes.length == 1) await firstRelease.future;
    });

    final first = queue.enqueue(const msg.PlayerStateChangedMessage(true));
    final second = queue.enqueue(
      const msg.NowPlayingChangedMessage(
        '害怕',
        '孙燕姿',
        'Start',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(writes, hasLength(1));
    expect(writes.first, endsWith('\n'));
    expect(json.decode(writes.first)['type'], 'PlayerStateChangedMessage');

    firstRelease.complete();
    await Future.wait([first, second]);

    expect(writes, hasLength(2));
    expect(writes[1], endsWith('\n'));
    expect(json.decode(writes[1])['message']['title'], '害怕');
  });

  test('a failed frame invalidates queued messages but the queue recovers',
      () async {
    var attempts = 0;
    final writes = <String>[];
    final queue = DesktopLyricMessageQueue((frame) async {
      attempts += 1;
      if (attempts == 1) throw StateError('pipe closed');
      writes.add(frame);
    });

    final failed = queue.enqueue(const msg.PlayerStateChangedMessage(true));
    final dropped = queue.enqueue(const msg.PlayerStateChangedMessage(false));

    await expectLater(
      failed,
      throwsA(isA<StateError>()),
    );
    await dropped;
    expect(writes, isEmpty);

    await queue.enqueue(const msg.PlayerStateChangedMessage(false));

    expect(writes, hasLength(1));
    expect(json.decode(writes.single)['message']['playing'], false);
  });

  test('recovers with a state snapshot before the next frame', () async {
    var attempts = 0;
    final writes = <String>[];
    final queue = DesktopLyricMessageQueue(
      (frame) async {
        attempts += 1;
        if (attempts == 1) throw StateError('pipe closed');
        writes.add(frame);
      },
      onRecovery: () async {
        writes.add('state snapshot');
      },
    );

    await expectLater(
      queue.enqueue(const msg.NowPlayingChangedMessage('旧歌', '旧作者', '旧专辑')),
      throwsA(isA<StateError>()),
    );
    await queue.enqueue(
      const msg.LyricLineChangedMessage('新歌词', Duration(seconds: 1), null),
    );

    expect(writes, [
      'state snapshot',
      contains('LyricLineChangedMessage'),
    ]);
  });
}
