enum PlaybackSnapshotState { idle, paused, playing }

enum ExclusiveFailureReason {
  unsupportedFormat,
  deviceUnavailable,
  initialization,
  recovery,
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.path,
    required this.position,
    required this.volume,
    required this.state,
  });

  final String? path;
  final Duration position;
  final double volume;
  final PlaybackSnapshotState state;
}

abstract interface class OutputModeOperations {
  PlaybackSnapshot captureSnapshot();

  void rebuildFromSnapshot(
    PlaybackSnapshot snapshot, {
    required bool exclusive,
  });

  void disposeWasapi();
}

class OutputModeSwitchResult {
  const OutputModeSwitchResult({
    required this.actualExclusive,
    this.failureReason,
  });

  final bool actualExclusive;
  final ExclusiveFailureReason? failureReason;
}

class WasapiInitializationException implements Exception {
  const WasapiInitializationException(this.reason);

  final ExclusiveFailureReason reason;
}

class OutputModeSwitchCoordinator {
  const OutputModeSwitchCoordinator(this.operations);

  final OutputModeOperations operations;

  OutputModeSwitchResult switchMode(bool exclusive) {
    late final PlaybackSnapshot snapshot;
    try {
      snapshot = operations.captureSnapshot();
    } catch (_) {
      return const OutputModeSwitchResult(
        actualExclusive: false,
        failureReason: ExclusiveFailureReason.recovery,
      );
    }

    if (!exclusive) {
      try {
        operations.disposeWasapi();
        operations.rebuildFromSnapshot(snapshot, exclusive: false);
        return const OutputModeSwitchResult(actualExclusive: false);
      } catch (_) {
        return const OutputModeSwitchResult(
          actualExclusive: false,
          failureReason: ExclusiveFailureReason.recovery,
        );
      }
    }

    ExclusiveFailureReason failureReason;
    try {
      operations.rebuildFromSnapshot(snapshot, exclusive: true);
      return const OutputModeSwitchResult(actualExclusive: true);
    } on WasapiInitializationException catch (error) {
      failureReason = error.reason;
    } catch (_) {
      failureReason = ExclusiveFailureReason.initialization;
    }

    try {
      operations.disposeWasapi();
      operations.rebuildFromSnapshot(snapshot, exclusive: false);
      return OutputModeSwitchResult(
        actualExclusive: false,
        failureReason: failureReason,
      );
    } catch (_) {
      return const OutputModeSwitchResult(
        actualExclusive: false,
        failureReason: ExclusiveFailureReason.recovery,
      );
    }
  }
}
