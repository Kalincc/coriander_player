import 'dart:math';

import 'package:coriander_player/lyric/lyric.dart';

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

int lyricLineIndexAt(
  List<LyricLine> lines,
  Duration audioPosition,
  Duration offset,
) {
  if (lines.isEmpty) return 0;

  final lyricPosition = lyricClockPosition(audioPosition, offset);
  final nextLine = lines.indexWhere((line) => line.start > lyricPosition);
  return nextLine == -1 ? lines.length - 1 : max(nextLine - 1, 0);
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
