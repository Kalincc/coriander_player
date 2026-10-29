import 'package:coriander_player/library/audio_path_key.dart';
import 'package:flutter/painting.dart';

/// Shared across views and Audio snapshots, including pending and missing covers.
class ArtworkCache {
  ArtworkCache({required this.load, this.capacity = 256})
      : assert(capacity > 0);

  final Future<ImageProvider?> Function(String path, int width, int height)
      load;
  final int capacity;
  final _entries = <(String, int, int, int, int), Future<ImageProvider?>>{};

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

    late final Future<ImageProvider?> pending;
    pending = Future<ImageProvider?>.sync(() => load(path, width, height))
        .catchError((Object error, StackTrace trace) {
      if (identical(_entries[key], pending)) _entries.remove(key);
      Error.throwWithStackTrace(error, trace);
    });
    _entries[key] = pending;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    return pending;
  }

  void clear() => _entries.clear();
}
