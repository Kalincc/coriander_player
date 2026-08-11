import 'package:coriander_player/library/playback_history_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes a qualified playback event with its listened duration', () {
    final event = PlaybackHistoryEvent(
      path: 'D:/music/first.flac',
      startedAt: DateTime.utc(2026, 8, 11, 12, 30),
      listened: const Duration(minutes: 3, seconds: 3),
      qualified: true,
    );

    expect(event.toMap(), {
      'path': 'D:/music/first.flac',
      'startedAt': '2026-08-11T12:30:00.000Z',
      'listenedMs': 183000,
      'qualified': true,
    });

    final restored = PlaybackHistoryEvent.fromMap(event.toMap());
    expect(restored.path, event.path);
    expect(restored.startedAt, event.startedAt);
    expect(restored.listened, event.listened);
    expect(restored.qualified, isTrue);
  });
}
