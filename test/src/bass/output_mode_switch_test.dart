import 'package:coriander_player/src/bass/output_mode_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    path: 'D:/music/song.flac',
    position: Duration(seconds: 42),
    volume: 0.7,
    state: PlaybackSnapshotState.playing,
  );

  test('switches to exact exclusive mode when rebuilding succeeds', () {
    final operations = _FakeOperations(playing);

    final result = OutputModeSwitchCoordinator(operations).switchMode(true);

    expect(result.actualExclusive, isTrue);
    expect(result.failureReason, isNull);
    expect(operations.calls, ['capture', 'rebuild:true']);
    expect(operations.snapshots.single, playing);
  });

  test('disables WASAPI and rebuilds shared mode from the snapshot', () {
    final operations = _FakeOperations(playing);

    final result = OutputModeSwitchCoordinator(operations).switchMode(false);

    expect(result.actualExclusive, isFalse);
    expect(result.failureReason, isNull);
    expect(operations.calls, ['capture', 'dispose', 'rebuild:false']);
  });

  test('exclusive format failure transactionally restores shared playback', () {
    final operations = _FakeOperations(
      playing,
      exclusiveFailure: const WasapiInitializationException(
        ExclusiveFailureReason.unsupportedFormat,
      ),
    );

    final result = OutputModeSwitchCoordinator(operations).switchMode(true);

    expect(result.actualExclusive, isFalse);
    expect(result.failureReason, ExclusiveFailureReason.unsupportedFormat);
    expect(
      operations.calls,
      ['capture', 'rebuild:true', 'dispose', 'rebuild:false'],
    );
    expect(operations.snapshots, [playing, playing]);
  });

  test('preserves paused and idle snapshots without fabricating state', () {
    const paused = PlaybackSnapshot(
      path: 'D:/music/paused.flac',
      position: Duration(seconds: 9),
      volume: 0.4,
      state: PlaybackSnapshotState.paused,
    );
    const idle = PlaybackSnapshot(
      path: null,
      position: Duration.zero,
      volume: 1,
      state: PlaybackSnapshotState.idle,
    );

    for (final snapshot in [paused, idle]) {
      final operations = _FakeOperations(snapshot);
      OutputModeSwitchCoordinator(operations).switchMode(true);
      expect(operations.snapshots.single, snapshot);
    }
  });

  test('reports recovery failure when shared rebuilding also fails', () {
    final operations = _FakeOperations(
      playing,
      exclusiveFailure: const WasapiInitializationException(
        ExclusiveFailureReason.deviceUnavailable,
      ),
      sharedFailure: StateError('shared failed'),
    );

    final result = OutputModeSwitchCoordinator(operations).switchMode(true);

    expect(result.actualExclusive, isFalse);
    expect(result.failureReason, ExclusiveFailureReason.recovery);
    expect(
      operations.calls,
      ['capture', 'rebuild:true', 'dispose', 'rebuild:false'],
    );
  });
}

class _FakeOperations implements OutputModeOperations {
  _FakeOperations(
    this.snapshot, {
    this.exclusiveFailure,
    this.sharedFailure,
  });

  final PlaybackSnapshot snapshot;
  final Object? exclusiveFailure;
  final Object? sharedFailure;
  final calls = <String>[];
  final snapshots = <PlaybackSnapshot>[];

  @override
  PlaybackSnapshot captureSnapshot() {
    calls.add('capture');
    return snapshot;
  }

  @override
  void disposeWasapi() => calls.add('dispose');

  @override
  void rebuildFromSnapshot(
    PlaybackSnapshot snapshot, {
    required bool exclusive,
  }) {
    calls.add('rebuild:$exclusive');
    snapshots.add(snapshot);
    final failure = exclusive ? exclusiveFailure : sharedFailure;
    if (failure != null) throw failure;
  }
}
