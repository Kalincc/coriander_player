import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/lyric_search_normalizer.dart';
import 'package:flutter/foundation.dart';

@immutable
class LyricSearchLine {
  final int startMs;
  final String text;
  final String? translation;
  final List<String>? _persistedSearchForms;

  const LyricSearchLine({
    required this.startMs,
    required this.text,
    this.translation,
    List<String>? searchForms,
  }) : _persistedSearchForms = searchForms;

  String get normalizedText => text.toLowerCase();

  List<String> get searchForms =>
      _persistedSearchForms ??
      {
        ...lyricSearchFormsFor(text),
        if (translation != null) ...lyricSearchFormsFor(translation!),
      }.toList(growable: false);

  Map<String, Object> toJson() => {
        'startMs': startMs,
        'text': text,
        if (translation?.trim().isNotEmpty == true) 'translation': translation!,
        'searchForms': searchForms,
      };

  factory LyricSearchLine.fromJson(Map<String, dynamic> json) =>
      LyricSearchLine(
        startMs: json['startMs'] as int,
        text: json['text'] as String,
        translation: json['translation'] as String?,
        searchForms: json['searchForms'] == null
            ? null
            : List<String>.from(json['searchForms'] as List),
      );

  @override
  bool operator ==(Object other) =>
      other is LyricSearchLine &&
      startMs == other.startMs &&
      text == other.text &&
      translation == other.translation &&
      listEquals(searchForms, other.searchForms);

  @override
  int get hashCode =>
      Object.hash(startMs, text, translation, Object.hashAll(searchForms));
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
  return searchLyricEntriesForCompiledQuery(
    query: CompiledLyricQuery.compile(query),
    entries: entries,
    audios: audios,
  );
}

List<LyricSearchMatch> searchLyricEntriesForCompiledQuery({
  required CompiledLyricQuery query,
  required Map<String, LyricIndexEntry> entries,
  required Iterable<Audio> audios,
}) {
  if (query.isEmpty) return [];

  final matches = <LyricSearchMatch>[];
  for (final audio in audios) {
    final match = searchLyricEntryForCompiledQuery(
      query: query,
      entry: entries[audio.path],
      audio: audio,
    );
    if (match != null) matches.add(match);
  }
  return matches;
}

LyricSearchMatch? searchLyricEntryForCompiledQuery({
  required CompiledLyricQuery query,
  required LyricIndexEntry? entry,
  required Audio audio,
}) {
  if (entry == null) return null;

  final matchingLines = entry.lines
      .where(
        (line) =>
            line.text.trim().isNotEmpty && query.matches(line.searchForms),
      )
      .toSet()
      .toList()
    ..sort((left, right) => left.startMs.compareTo(right.startMs));

  return matchingLines.isEmpty
      ? null
      : LyricSearchMatch(audio: audio, lines: matchingLines);
}
