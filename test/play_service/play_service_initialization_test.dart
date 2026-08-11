import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads the queue before attaching playback history', () async {
    final calls = <String>[];
    final initializer = PlaybackDataInitializer(
      loadQueue: (Iterable<Audio> library) async {
        calls.add('queue:${library.length}');
      },
      loadHistory: () async {
        calls.add('history');
      },
    );

    await initializer.initialize(const <Audio>[]);

    expect(calls, ['queue:0', 'history']);
  });
}
