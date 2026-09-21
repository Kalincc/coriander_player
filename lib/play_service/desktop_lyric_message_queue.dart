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

  Future<void> enqueue(msg.Message message) {
    final frame = '${message.buildMessageJson()}\n';
    final operation = _tail.then((_) => _writeFrame(frame));

    // Keep the queue usable after one failed pipe write. The individual
    // operation still exposes its error to the caller.
    _tail = operation.catchError((_) {});
    return operation;
  }
}
