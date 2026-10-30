import 'dart:async';
import 'dart:collection';

import 'package:coriander_player/library/audio_path_key.dart';
import 'package:flutter/painting.dart';

/// Shared across views and Audio snapshots, including pending and missing covers.
class ArtworkCache {
  ArtworkCache({
    required this.load,
    this.capacity = 256,
    this.maxConcurrentLoads = 2,
  })  : assert(capacity > 0),
        assert(maxConcurrentLoads > 0);

  final Future<ImageProvider?> Function(String path, int width, int height)
      load;
  final int capacity;
  final int maxConcurrentLoads;
  final _entries = <(String, int, int, int, int), Future<ImageProvider?>>{};
  final _pending = <(String, int, int, int, int), Future<ImageProvider?>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;

  Future<ImageProvider?> get({
    required String path,
    required int modified,
    required int created,
    required int width,
    required int height,
  }) {
    final key = (audioPathKey(path), modified, created, width, height);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final inFlight = _pending[key];
    if (inFlight != null) return inFlight;

    late final Future<ImageProvider?> pending;
    pending = _loadLimited(path, width, height).whenComplete(() {
      if (identical(_pending[key], pending)) _pending.remove(key);
    }).catchError((Object error, StackTrace trace) {
      if (identical(_entries[key], pending)) _entries.remove(key);
      Error.throwWithStackTrace(error, trace);
    });
    _entries[key] = pending;
    _pending[key] = pending;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    return pending;
  }

  Future<ImageProvider?> _loadLimited(
      String path, int width, int height) async {
    if (_active >= maxConcurrentLoads) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await load(path, width, height);
    } finally {
      if (_waiting.isNotEmpty) {
        // Transfer this slot to the next waiter before accepting newer work.
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  void clear() {
    _entries.clear();
    _pending.clear();
  }
  // ponytail: queued requests finish after navigation; cancel only if profiling
  // shows sustained scroll queues. Running native work cannot be cancelled here.
}
