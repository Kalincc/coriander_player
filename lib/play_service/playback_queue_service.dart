import 'dart:collection';
import 'dart:io';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class PlaybackQueueService extends ChangeNotifier {
  PlaybackQueueService({required this.store});

  static const _fileName = 'playback_queue.json';
  static const _version = 1;

  final LocalJsonStore store;
  final List<Audio> _items = [];
  String? _currentPath;
  Duration _savedPosition = Duration.zero;

  UnmodifiableListView<Audio> get items => UnmodifiableListView(_items);
  String? get currentPath => _currentPath;
  Duration get savedPosition => _savedPosition;

  int get currentIndex {
    final currentPath = _currentPath;
    if (currentPath == null) return -1;
    return _items.indexWhere((audio) => _samePath(audio.path, currentPath));
  }

  Future<void> load(Iterable<Audio> library) async {
    final raw = await store.read(_fileName);
    final saved = raw is Map ? raw : const <Object?, Object?>{};
    final resolved = _resolvePaths(saved['items'], library);
    final current = _resolveCurrentPath(saved['currentPath'], resolved);
    final position = current == null
        ? Duration.zero
        : Duration(milliseconds: _asNonNegativeInt(saved['positionMs']));

    _apply(resolved, current, position);
    if (raw != null &&
        !_matchesSavedQueue(saved, resolved, current, position)) {
      await _persist();
    }
  }

  Future<void> setQueue(
    Iterable<Audio> items, {
    String? currentPath,
    Duration position = Duration.zero,
  }) async {
    final queue = _deduplicate(items);
    final current = _resolveCurrentPath(currentPath, queue);
    _apply(queue, current,
        current == null ? Duration.zero : _nonNegative(position));
    await _persist();
  }

  Future<bool> append(Audio audio) async {
    if (_containsPath(_items, audio.path)) return false;

    _items.add(audio);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> insertNext(Audio audio) async {
    if (_containsPath(_items, audio.path)) return false;

    final index = currentIndex;
    _items.insert(index < 0 ? _items.length : index + 1, audio);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> removeAt(int index) async {
    if (index < 0 || index >= _items.length) return false;

    final removed = _items.removeAt(index);
    if (_currentPath != null && _samePath(removed.path, _currentPath!)) {
      _currentPath = null;
      _savedPosition = Duration.zero;
    }
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex > _items.length) return;

    var destination = newIndex;
    if (oldIndex < destination) destination--;
    if (destination == oldIndex) return;

    final item = _items.removeAt(oldIndex);
    _items.insert(destination, item);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    if (_items.isEmpty &&
        _currentPath == null &&
        _savedPosition == Duration.zero) {
      return;
    }

    _apply(const [], null, Duration.zero);
    await _persist();
  }

  Future<void> reconcile(Iterable<Audio> library) async {
    final resolved = _resolvePaths(_items.map((audio) => audio.path), library);
    final current = _resolveCurrentPath(_currentPath, resolved);
    final position = current == null ? Duration.zero : _savedPosition;
    if (_sameState(resolved, current, position)) return;

    _apply(resolved, current, position);
    await _persist();
  }

  Future<void> setCurrent({
    required Audio? audio,
    required Duration position,
  }) async {
    if (audio == null) {
      if (_currentPath == null && _savedPosition == Duration.zero) return;
      _apply(_items, null, Duration.zero);
      await _persist();
      return;
    }

    if (!_containsPath(_items, audio.path)) {
      _items.add(audio);
    }
    final current = _items.firstWhere(
      (item) => _samePath(item.path, audio.path),
    );
    _apply(_items, current.path, _nonNegative(position));
    await _persist();
  }

  List<Audio> _resolvePaths(Object? rawPaths, Iterable<Audio> library) {
    final byPath = <String, Audio>{};
    for (final audio in library) {
      byPath.putIfAbsent(_pathKey(audio.path), () => audio);
    }
    if (rawPaths is! Iterable) return const [];

    final result = <Audio>[];
    final seen = <String>{};
    for (final rawPath in rawPaths) {
      if (rawPath is! String) continue;
      final key = _pathKey(rawPath);
      final audio = byPath[key];
      if (audio != null && seen.add(key)) result.add(audio);
    }
    return result;
  }

  List<Audio> _deduplicate(Iterable<Audio> items) {
    final result = <Audio>[];
    final seen = <String>{};
    for (final audio in items) {
      if (seen.add(_pathKey(audio.path))) result.add(audio);
    }
    return result;
  }

  String? _resolveCurrentPath(Object? rawPath, Iterable<Audio> items) {
    if (rawPath is! String) return null;
    for (final audio in items) {
      if (_samePath(audio.path, rawPath)) return audio.path;
    }
    return null;
  }

  bool _matchesSavedQueue(
    Map saved,
    List<Audio> items,
    String? currentPath,
    Duration position,
  ) {
    final rawItems = saved['items'];
    if (saved['version'] != _version || rawItems is! List) return false;
    if (rawItems.length != items.length) return false;
    for (var index = 0; index < items.length; index++) {
      if (rawItems[index] is! String ||
          !_samePath(rawItems[index] as String, items[index].path)) {
        return false;
      }
    }
    return _samePathOrNull(saved['currentPath'], currentPath) &&
        _asNonNegativeInt(saved['positionMs']) == position.inMilliseconds;
  }

  bool _sameState(
    List<Audio> items,
    String? currentPath,
    Duration position,
  ) {
    if (_items.length != items.length ||
        !_samePathOrNull(_currentPath, currentPath) ||
        _savedPosition != position) {
      return false;
    }
    for (var index = 0; index < items.length; index++) {
      if (!_samePath(_items[index].path, items[index].path)) return false;
    }
    return true;
  }

  void _apply(List<Audio> items, String? currentPath, Duration position) {
    final changed = !_sameState(items, currentPath, position);
    _items
      ..clear()
      ..addAll(items);
    _currentPath = currentPath;
    _savedPosition = position;
    if (changed) notifyListeners();
  }

  Future<void> _persist() => store.writeAtomically(_fileName, {
        'version': _version,
        'items': _items.map((audio) => audio.path).toList(growable: false),
        'currentPath': _currentPath,
        'positionMs': _savedPosition.inMilliseconds,
      });

  bool _containsPath(Iterable<Audio> items, String path) =>
      items.any((audio) => _samePath(audio.path, path));

  bool _samePath(String first, String second) =>
      _pathKey(first) == _pathKey(second);

  bool _samePathOrNull(Object? first, String? second) {
    if (first == null || second == null) return first == second;
    return first is String && _samePath(first, second);
  }

  String _pathKey(String value) {
    final normalized = path.normalize(value);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;

  int _asNonNegativeInt(Object? value) {
    final parsed = value is num ? value.toInt() : 0;
    return parsed < 0 ? 0 : parsed;
  }
}
