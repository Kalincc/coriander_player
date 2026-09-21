import 'package:desktop_lyric/message.dart' as msg;

typedef DesktopLyricFrameWriter = Future<void> Function(String frame);

/// Serializes messages sent to the desktop lyric companion.
///
/// The companion consumes newline-delimited JSON. Keeping a single future tail
/// guarantees that a later frame cannot overtake an earlier frame, even when a
/// write or flush is temporarily delayed.
class DesktopLyricMessageQueue {
  DesktopLyricMessageQueue(this._writeFrame);

  final DesktopLyricFrameWriter _writeFrame;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  Future<void> enqueue(msg.Message message) {
    final frame = '${message.buildMessageJson()}\n';
    final generation = _generation;
    final operation = _tail.then((_) async {
      // A failed write invalidates every frame that was already queued behind
      // it. Sending those frames would let a lyric update survive a dropped
      // NowPlaying update and recreate the stale-metadata bug.
      if (generation != _generation) return;

      try {
        await _writeFrame(frame);
      } catch (_) {
        if (generation == _generation) {
          _generation += 1;
        }
        rethrow;
      }
    });

    // Keep the queue usable after one failed pipe write. The individual
    // operation still exposes its error to the caller, while queued operations
    // observe the generation change and complete without writing.
    _tail = operation.catchError((Object _, StackTrace __) {});
    return operation;
  }
}
