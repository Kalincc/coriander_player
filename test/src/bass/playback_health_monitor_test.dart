import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal progress is silent; loop stalls and buffer stalls are diagnosed',
      () {
    final monitor = PlaybackHealthMonitor();
    expect(monitor.observe(PlayerState.playing, 0, Duration.zero), isNull);
    expect(
        monitor.observe(
            PlayerState.playing, .033, const Duration(milliseconds: 33)),
        isNull);
    expect(monitor.observe(PlayerState.playing, 2, const Duration(seconds: 2)),
        contains('event-loop-gap'));
    monitor.reset();
    expect(monitor.observe(PlayerState.stalled, 2, const Duration(seconds: 3)),
        contains('stalled'));
    expect(
        monitor.observe(
            PlayerState.stalled, 2, const Duration(milliseconds: 3033)),
        isNull);
    monitor.reset();
    expect(
        monitor.observe(
            PlayerState.pausedDevice, 2, const Duration(seconds: 4)),
        contains('pausedDevice'));
  });

  test(
      'a frozen playing position is rate limited and reset ignores manual pauses',
      () {
    final monitor = PlaybackHealthMonitor();
    monitor.observe(PlayerState.playing, 1, Duration.zero);
    String? report;
    for (var i = 1; i <= 20; i++) {
      report ??= monitor.observe(
          PlayerState.playing, 1, Duration(milliseconds: i * 33));
    }
    expect(report, contains('position-not-advancing'));
    expect(
        monitor.observe(
            PlayerState.playing, 1, const Duration(milliseconds: 700)),
        isNull);
    monitor.reset();
    expect(
        monitor.observe(PlayerState.playing, 10, const Duration(seconds: 20)),
        isNull);
  });
}
