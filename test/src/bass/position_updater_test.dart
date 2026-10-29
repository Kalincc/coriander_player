import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('repeated starts keep one timer and stop cancels all progress',
      (tester) async {
    var ticks = 0;
    final updater = PlaybackPositionUpdater(() => ticks++);
    updater.start();
    updater.start();
    await tester.pump(const Duration(milliseconds: 99));
    expect(ticks, 3);
    updater.stop();
    await tester.pump(const Duration(milliseconds: 99));
    expect(ticks, 3);
    updater.start();
    await tester.pump(const Duration(milliseconds: 33));
    expect(ticks, 4);
    updater.stop();
  });

  testWidgets('completion can stop the timer after exactly one notification',
      (tester) async {
    var completed = 0;
    late final PlaybackPositionUpdater updater;
    updater = PlaybackPositionUpdater(() {
      completed++;
      updater.stop();
    });
    updater.start();
    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
  });
}
