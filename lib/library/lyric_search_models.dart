import 'package:coriander_player/library/audio_library.dart';
import 'package:flutter/foundation.dart';

@immutable
class LyricSearchLine {
  final int startMs;
  final String text;

  const LyricSearchLine({required this.startMs, required this.text});

  String get normalizedText => text.toLowerCase();

  Map<String, Object> toJson() => {'startMs': startMs, 'text': text};

  factory LyricSearchLine.fromJson(Map<String, dynamic> json) =>
      LyricSearchLine(
        startMs: json['startMs'] as int,
        text: json['text'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is LyricSearchLine &&
      startMs == other.startMs &&
      text == other.text;

  @override
  int get hashCode => Object.hash(startMs, text);
}

@immutable
class LyricFileFingerprint {
  final int audioModified;
  final String? sidecarPath;
  final int? sidecarModified;

  const LyricFileFingerprint({
    required this.audioModified,
    this.sidecarPath,
    this.sidecarModified,
  });

  Map<String, Object> toJson() => {
        'audioModified': audioModified,
        if (sidecarPath != null) 'sidecarPath': sidecarPath!,
        if (sidecarModified != null) 'sidecarModified': sidecarModified!,
      };

  factory LyricFileFingerprint.fromJson(Map<String, dynamic> json) =>
      LyricFileFingerprint(
        audioModified: json['audioModified'] as int,
        sidecarPath: json['sidecarPath'] as String?,
        sidecarModified: json['sidecarModified'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is LyricFileFingerprint &&
      audioModified == other.audioModified &&
      sidecarPath == other.sidecarPath &&
      sidecarModified == other.sidecarModified;

  @override
  int get hashCode => Object.hash(audioModified, sidecarPath, sidecarModified);
}

@immutable
class LyricIndexEntry {
  final String audioPath;
  final LyricFileFingerprint fingerprint;
  final List<LyricSearchLine> lines;

  LyricIndexEntry({
    required this.audioPath,
    required this.fingerprint,
    required List<LyricSearchLine> lines,
  }) : lines = List.unmodifiable(lines);

  Map<String, Object> toJson() => {
        'audioPath': audioPath,
        'fingerprint': fingerprint.toJson(),
        'lines': lines.map((line) => line.toJson()).toList(),
      };

  factory LyricIndexEntry.fromJson(Map<String, dynamic> json) =>
      LyricIndexEntry(
        audioPath: json['audioPath'] as String,
        fingerprint: LyricFileFingerprint.fromJson(
          Map<String, dynamic>.from(json['fingerprint'] as Map),
        ),
        lines: (json['lines'] as List)
            .map(
              (line) => LyricSearchLine.fromJson(
                Map<String, dynamic>.from(line as Map),
              ),
            )
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is LyricIndexEntry &&
      audioPath == other.audioPath &&
      fingerprint == other.fingerprint &&
      listEquals(lines, other.lines);

  @override
  int get hashCode =>
      Object.hash(audioPath, fingerprint, Object.hashAll(lines));
}

@immutable
class LyricSearchMatch {
  final Audio audio;
  final List<LyricSearchLine> lines;

  LyricSearchMatch({
    required this.audio,
    required List<LyricSearchLine> lines,
  }) : lines = List.unmodifiable(lines);
}

List<LyricSearchMatch> searchLyricEntries({
  required String query,
  required Map<String, LyricIndexEntry> entries,
  required Iterable<Audio> audios,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return [];

  final matches = <LyricSearchMatch>[];
  for (final audio in audios) {
    final entry = entries[audio.path];
    if (entry == null) continue;

    final matchingLines = entry.lines
        .where(
          (line) =>
              line.text.trim().isNotEmpty &&
              line.normalizedText.contains(normalizedQuery),
        )
        .toSet()
        .toList()
      ..sort((left, right) => left.startMs.compareTo(right.startMs));

    if (matchingLines.isNotEmpty) {
      matches.add(LyricSearchMatch(audio: audio, lines: matchingLines));
    }
  }
  return matches;
}
