import 'dart:convert';

import 'package:coriander_player/lyric/lyric.dart';

class Krc extends Lyric {
  Krc(super.lines);

  static Krc fromKrcText(String krc) {
    final List<KrcLine> lines = [];
    String? languageFrame;

    final splited = krc.split("\n");
    for (final raw in splited) {
      final item = raw.trim();
      if (item.isEmpty) continue;
      if (item.startsWith('[language:') && item.endsWith(']')) {
        languageFrame ??= item.substring(10, item.length - 1);
        continue;
      }

      final krcLine = KrcLine.fromLine(item);

      if (krcLine == null) continue;

      lines.add(krcLine);
    }

    if (languageFrame != null) {
      // Translation metadata is optional; an invalid frame must not hide text.
      try {
        final languageMap =
            json.decode(utf8.decode(base64.decode(languageFrame)));
        final content = languageMap is Map ? languageMap['content'] : null;
        if (content is List) {
          for (final item in content) {
            if (item is! Map || item['type'] != 1) continue;
            final translations = item['lyricContent'];
            if (translations is! List) continue;
            for (var i = 0; i < lines.length && i < translations.length; i++) {
              final entry = translations[i];
              if (entry is List && entry.isNotEmpty && entry.first is String) {
                lines[i].translation = entry.first as String;
              }
            }
            break;
          }
        }
      } on FormatException {/* Keep the original lyric. */}
    }

    // 添加空白
    final List<KrcLine> fommatedLines = [];
    final firstLine = lines.firstOrNull;
    if (firstLine != null && firstLine.start > const Duration(seconds: 5)) {
      fommatedLines.add(KrcLine(Duration.zero, firstLine.start, []));
    }
    for (int i = 0; i < lines.length - 1; ++i) {
      fommatedLines.add(lines[i]);
      final transitionStart = lines[i].start + lines[i].length;
      final transitionLength = lines[i + 1].start - transitionStart;
      if (transitionLength > const Duration(seconds: 5)) {
        fommatedLines.add(KrcLine(transitionStart, transitionLength, []));
      }
    }
    final lastLine = lines.lastOrNull;
    if (lastLine != null) {
      fommatedLines.add(lastLine);
    }

    return Krc(fommatedLines);
  }

  @override
  String toString() {
    return (lines as List<SyncLyricLine>).toString();
  }
}

class KrcLine extends SyncLyricLine {
  KrcLine(super.start, super.length, super.words, [super.translation]);

  static KrcLine? fromLine(String line, [String? translation]) {
    final match = RegExp(r'^\[(\d+),(\d+)\](.*)$').firstMatch(line);
    if (match == null) return null;
    final startMs = int.tryParse(match[1]!);
    final lengthMs = int.tryParse(match[2]!);
    if (startMs == null || lengthMs == null) return null;
    final start = Duration(milliseconds: startMs);
    final length = Duration(milliseconds: lengthMs);

    final splitedContent = match[3]!.split("<");
    final List<KrcWord> words = [];
    for (final item in splitedContent) {
      final qrcWord = KrcWord.fromWord(item, start);

      if (qrcWord == null) continue;

      words.add(qrcWord);
    }

    return KrcLine(start, length, words, translation);
  }
}

class KrcWord extends SyncLyricWord {
  KrcWord(super.start, super.length, super.content);

  static KrcWord? fromWord(String word, Duration lineStart) {
    final splitedWord = word.split(">");
    if (splitedWord.length != 2) return null;

    final splitedTime = splitedWord[0].split(",");

    if (splitedTime.length < 2) return null;

    final Duration start = Duration(
          milliseconds: int.tryParse(splitedTime[0]) ?? 0,
        ) +
        lineStart;
    final Duration length = Duration(
      milliseconds: int.tryParse(splitedTime[1]) ?? 0,
    );

    return KrcWord(start, length, splitedWord[1]);
  }
}
