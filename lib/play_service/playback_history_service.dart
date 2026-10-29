import 'dart:collection';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/audio_path_key.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/library/playback_history_models.dart';
import 'package:flutter/foundation.dart';

const _historyFileName = 'play_history.json';
const _historyVersion = 1;
const _longTrackThreshold = Duration(seconds: 30);

class PlaybackHistoryService extends ChangeNotifier {
  PlaybackHistoryService({required this.store, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final LocalJsonStore store;
  final DateTime Function() _now;
  final List<PlaybackHistoryEvent> _events = [];
  _PlaybackSession? _session;
  Future<void> _persistChain = Future.value();
  bool _loadFailed = false;

  List<PlaybackHistoryEvent> get events =>
      UnmodifiableListView<PlaybackHistoryEvent>(_events);

  List<PlaybackHistoryEvent> get recent20 {
    final recent = List<PlaybackHistoryEvent>.from(_events)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(recent.take(20));
  }

  Future<void> load() async {
    List<PlaybackHistoryEvent> loaded = [];
    try {
      final raw = await store.read(_historyFileName);
      if (raw != null) {
        if (raw is! Map || raw['events'] is! List) {
          throw const FormatException('Invalid playback history');
        }
        loaded = (raw['events'] as List).map((item) {
          try {
            if (item is Map) return PlaybackHistoryEvent.fromMap(item);
          } catch (_) {
            throw const FormatException('Invalid playback history event');
          }
          throw const FormatException('Invalid playback history event');
        }).toList();
      }
      _loadFailed = false;
    } catch (error) {
      _loadFailed = true;
      debugPrint('[playback history] failed to load: $error');
      rethrow;
    }

    final retained = _retainRecent(loaded);
    _events
      ..clear()
      ..addAll(retained);
    notifyListeners();

    if (retained.length != loaded.length) {
      await _persist();
    }
  }

  Future<void> reconcileLibrary(Iterable<Audio> library,
      {bool removeMissing = true}) async {
    final available = {
      for (final audio in library) audioPathKey(audio.path): audio
    };
    final retained = _retainRecent(
      _events
          .where((event) =>
              !removeMissing || available.containsKey(audioPathKey(event.path)))
          .map((event) {
        final current = available[audioPathKey(event.path)];
        if (current == null || event.path == current.path) return event;
        return PlaybackHistoryEvent(
          path: current.path,
          startedAt: event.startedAt,
          listened: event.listened,
          qualified: event.qualified,
        );
      }),
    );
    final eventsChanged = !_sameEvents(_events, retained);
    final session = _session;
    final currentAudio =
        session == null ? null : available[audioPathKey(session.audio.path)];
    final sessionChanged =
        removeMissing && session != null && currentAudio == null;
    if (session != null && currentAudio != null) session.audio = currentAudio;
    if (!eventsChanged && !sessionChanged) return;

    if (eventsChanged) {
      _events
        ..clear()
        ..addAll(retained);
    }
    if (sessionChanged) {
      _session = null;
    }
    notifyListeners();
    if (eventsChanged) await _persist();
  }

  void startSession(
    Audio audio, {
    DateTime? startedAt,
    Duration initialPosition = Duration.zero,
  }) {
    _session = _PlaybackSession(
      audio,
      startedAt ?? _now(),
      initialPosition,
    );
  }

  void recordPosition(Duration position) {
    final session = _session;
    if (session == null) return;
    if (position < session.positionBaseline) {
      session.positionBaseline = position;
      return;
    }

    session.listened += position - session.positionBaseline;
    session.positionBaseline = position;
  }

  void recordSeek(Duration position) {
    final session = _session;
    if (session == null) return;
    session.positionBaseline = position;
  }

  Future<void> endSession({bool flush = false}) async {
    final session = _session;
    _session = null;
    if (session == null || !_qualifies(session)) {
      if (flush) await _persist();
      return;
    }

    _events.add(
      PlaybackHistoryEvent(
        path: session.audio.path,
        startedAt: session.startedAt,
        listened: session.listened,
        qualified: true,
      ),
    );
    final retained = _retainRecent(_events);
    _events
      ..clear()
      ..addAll(retained);
    notifyListeners();
    await _persist();
  }

  bool _qualifies(_PlaybackSession session) =>
      session.listened >= _qualificationThreshold(session.audio);

  Duration _qualificationThreshold(Audio audio) {
    if (audio.duration <= 0) return _longTrackThreshold;
    final halfDuration = Duration(milliseconds: audio.duration * 500);
    return halfDuration < _longTrackThreshold
        ? halfDuration
        : _longTrackThreshold;
  }

  List<PlaybackHistoryEvent> _retainRecent(
    Iterable<PlaybackHistoryEvent> events,
  ) {
    final cutoff = _oneYearBefore(_now());
    return events.where((event) => !event.startedAt.isBefore(cutoff)).toList();
  }

  bool _sameEvents(
    List<PlaybackHistoryEvent> current,
    List<PlaybackHistoryEvent> next,
  ) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index] != next[index]) return false;
    }
    return true;
  }

  Future<void> _persist() async {
    if (_loadFailed) {
      throw StateError('History must be loaded successfully before saving');
    }
    final snapshot = {
      'version': _historyVersion,
      'events': _events.map((event) => event.toMap()).toList(),
    };
    final nextWrite = _persistChain
        .catchError((_) {})
        .then((_) => store.writeAtomically(_historyFileName, snapshot));
    _persistChain = nextWrite.catchError((error) {
      debugPrint('[playback history] failed to save: $error');
    });
    await nextWrite;
  }
}

class _PlaybackSession {
  _PlaybackSession(this.audio, this.startedAt, this.initialPosition)
      : positionBaseline = initialPosition;

  Audio audio;
  final DateTime startedAt;
  final Duration initialPosition;
  Duration positionBaseline;
  var listened = Duration.zero;
}

DateTime _oneYearBefore(DateTime value) => value.isUtc
    ? DateTime.utc(
        value.year - 1,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
        value.millisecond,
        value.microsecond,
      )
    : DateTime(
        value.year - 1,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
        value.millisecond,
        value.microsecond,
      );
