class PlaybackHistoryEvent {
  const PlaybackHistoryEvent({
    required this.path,
    required this.startedAt,
    required this.listened,
    required this.qualified,
  });

  final String path;
  final DateTime startedAt;
  final Duration listened;
  final bool qualified;

  Map<String, Object> toMap() => {
        'path': path,
        'startedAt': startedAt.toIso8601String(),
        'listenedMs': listened.inMilliseconds,
        'qualified': qualified,
      };

  factory PlaybackHistoryEvent.fromMap(Map map) => PlaybackHistoryEvent(
        path: map['path'] as String,
        startedAt: DateTime.parse(map['startedAt'] as String),
        listened: Duration(milliseconds: map['listenedMs'] as int),
        qualified: map['qualified'] as bool,
      );
}
