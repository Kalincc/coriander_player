import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:flutter/foundation.dart';

@immutable
class LyricPresentation {
  final String primary;
  final String? translation;

  const LyricPresentation(this.primary, this.translation);
}

LyricPresentation presentLyricLine(
  LyricLine line, {
  required bool showTranslation,
}) {
  if (line is SyncLyricLine) {
    return LyricPresentation(
      line.content,
      showTranslation ? line.translation : null,
    );
  }

  if (line is LrcLine) {
    final separatorIndex = line.content.indexOf('┃');
    if (separatorIndex == -1) {
      return LyricPresentation(line.content, null);
    }

    final translation = line.content.substring(separatorIndex + 1);
    return LyricPresentation(
      line.content.substring(0, separatorIndex),
      showTranslation && translation.isNotEmpty ? translation : null,
    );
  }

  if (line is UnsyncLyricLine) {
    return LyricPresentation(line.content, null);
  }

  return const LyricPresentation('', null);
}

bool lyricHasTranslation(Lyric lyric) {
  return lyric.lines.any(
    (line) => presentLyricLine(line, showTranslation: true).translation != null,
  );
}
