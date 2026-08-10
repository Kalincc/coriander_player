const int lyricOffsetLimitMs = 10000;
const int lyricOffsetStepMs = 100;

int clampLyricOffsetMs(int value) {
  return value.clamp(-lyricOffsetLimitMs, lyricOffsetLimitMs);
}

Duration lyricClockPosition(Duration audioPosition, Duration offset) {
  return audioPosition - offset;
}

Duration lyricDisplayStart(Duration originalStart, Duration offset) {
  final displayStart = originalStart + offset;
  return displayStart.isNegative ? Duration.zero : displayStart;
}

double lyricWordProgress({
  required Duration audioPosition,
  required Duration wordStart,
  required Duration wordLength,
  required Duration offset,
}) {
  if (wordLength <= Duration.zero) return 0;

  final lyricPosition = lyricClockPosition(audioPosition, offset);
  final progress = (lyricPosition.inMicroseconds - wordStart.inMicroseconds) /
      wordLength.inMicroseconds;
  return progress.clamp(0.0, 1.0).toDouble();
}
