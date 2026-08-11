import 'dart:collection';

import 'package:coriander_player/library/audio_library.dart';
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
      if (raw is Map && raw['events'] is List) {
        loaded = (raw['events'] as List)
            .whereType<Map>()
            .map(PlaybackHistoryEvent.fromMap)
            .toList();
      }
    } catch (error) {
      debugPrint('[playback history] failed to load: $error');
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
    final listened = position >= session.initialPosition
        ? position - session.initialPosition
        : Duration.zero;
    if (listened <= session.listened) return;
    session.listened = listened;
  }

  Future<void> endSession() async {
    final session = _session;
    _session = null;
    if (session == null || !_qualifies(session)) return;

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

  Future<void> _persist() async {
    try {
      await store.writeAtomically(_historyFileName, {
        'version': _historyVersion,
        'events': _events.map((event) => event.toMap()).toList(),
      });
    } catch (error) {
      debugPrint('[playback history] failed to save: $error');
    }
  }
}

class _PlaybackSession {
  _PlaybackSession(this.audio, this.startedAt, this.initialPosition);

  final Audio audio;
  final DateTime startedAt;
  final Duration initialPosition;
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
