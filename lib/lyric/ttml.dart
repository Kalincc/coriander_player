import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:xml/xml.dart';

class Ttml extends Lrc {
  Ttml(List<LyricLine> lines) : super(lines, LrcSource.local);

  static Ttml? fromTtmlText(String text) {
    try {
      final document = XmlDocument.parse(
        text.trim().replaceFirst('\uFEFF', '').trim(),
      );
      if (document.rootElement.localName != 'tt') return null;

      final lines = <TtmlLine>[];
      final paragraphs = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.localName == 'p');
      for (final paragraph in paragraphs) {
        final line = _parseParagraph(paragraph);
        if (line != null) lines.add(line);
      }

      if (lines.isEmpty) return null;
      lines.sort((left, right) => left.start.compareTo(right.start));
      return Ttml(lines);
    } on XmlException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static TtmlLine? _parseParagraph(XmlElement paragraph) {
    final start = _parseTimestamp(paragraph.getAttribute('begin'));
    final end = _resolveEnd(
      start,
      paragraph.getAttribute('end'),
      paragraph.getAttribute('dur'),
    );
    final content = _visibleText(paragraph);
    if (start == null || end == null || end <= start || content.isEmpty) {
      return null;
    }

    final spans = paragraph.descendants
        .whereType<XmlElement>()
        .where((element) => element.localName == 'span')
        .toList();
    final words = <TtmlWord>[];
    for (var index = 0; index < spans.length; index++) {
      final span = spans[index];
      final wordStart = _parseTimestamp(span.getAttribute('begin'));
      final wordEnd = _resolveEnd(
            wordStart,
            span.getAttribute('end'),
            span.getAttribute('dur'),
          ) ??
          _nextWordStart(spans, index + 1);
      final wordContent = _visibleText(span);
      if (wordStart == null ||
          wordEnd == null ||
          wordEnd <= wordStart ||
          wordContent.isEmpty) {
        continue;
      }
      words.add(TtmlWord(wordStart, wordEnd - wordStart, wordContent));
    }

    return TtmlLine(start, end - start, words, content);
  }

  static Duration? _nextWordStart(List<XmlElement> spans, int from) {
    for (var index = from; index < spans.length; index++) {
      final start = _parseTimestamp(spans[index].getAttribute('begin'));
      if (start != null) return start;
    }
    return null;
  }

  static Duration? _resolveEnd(Duration? start, String? end, String? dur) {
    if (start == null) return null;
    final explicitEnd = _parseTimestamp(end);
    if (explicitEnd != null) return explicitEnd;
    final duration = _parseTimestamp(dur);
    return duration == null ? null : start + duration;
  }

  static Duration? _parseTimestamp(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final decimal = double.tryParse(trimmed);
    if (decimal != null && decimal >= 0) {
      return Duration(milliseconds: (decimal * 1000).round());
    }

    final match =
        RegExp(r'^(\d+):(\d{2}):(\d{2}(?:\.\d+)?)$').firstMatch(trimmed);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1)!);
    final minutes = int.tryParse(match.group(2)!);
    final seconds = double.tryParse(match.group(3)!);
    if (hours == null ||
        minutes == null ||
        seconds == null ||
        minutes >= 60 ||
        seconds >= 60) {
      return null;
    }
    return Duration(
      milliseconds: ((hours * 3600 + minutes * 60 + seconds) * 1000).round(),
    );
  }

  static String _visibleText(XmlNode node) {
    final buffer = StringBuffer();
    void collect(XmlNode current) {
      if (current is XmlText) {
        if (!current.value.contains(RegExp(r'[\r\n]'))) {
          buffer.write(current.value);
        }
        return;
      }
      for (final child in current.children) {
        collect(child);
      }
    }

    collect(node);
    return buffer.toString().trim();
  }
}

class TtmlLine extends SyncLyricLine {
  TtmlLine(super.start, super.length, super.words, String content) {
    this.content = content;
  }
}

class TtmlWord extends SyncLyricWord {
  TtmlWord(super.start, super.length, super.content);
}
