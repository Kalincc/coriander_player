import 'package:coriander_player/play_service/playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a newer playback request invalidates an older metadata callback', () {
    final gate = PlaybackRequestGate();

    final firstRequest = gate.begin();
    final latestRequest = gate.begin();

    expect(gate.isCurrent(firstRequest), isFalse);
    expect(gate.isCurrent(latestRequest), isTrue);
  });
}
