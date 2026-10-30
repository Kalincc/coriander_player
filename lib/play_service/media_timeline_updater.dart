import 'dart:async';

/// One native call at a time; ordinary ticks retain only the newest position.
class MediaTimelineUpdater {
  MediaTimelineUpdater({
    required this.send,
    this.onError,
    this.interval = const Duration(seconds: 1),
  });

  final Future<void> Function(int progress) send;
  final void Function(Object, StackTrace)? onError;
  final Duration interval;
  Timer? _timer;
  int? _pending;
  bool _running = false;
  bool _disposed = false;

  void update(int progress, {bool immediate = false}) {
    if (_disposed) return;
    _pending = progress;
    if (immediate) {
      _timer?.cancel();
      _timer = null;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_disposed || _running || _timer != null || _pending == null) return;
    final progress = _pending!;
    _pending = null;
    _running = true;
    _timer = Timer(interval, () {
      _timer = null;
      unawaited(_drain());
    });
    try {
      await send(progress);
    } catch (error, trace) {
      onError?.call(error, trace);
    } finally {
      _running = false;
      unawaited(_drain());
    }
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _timer?.cancel();
    _timer = null;
  }
}
