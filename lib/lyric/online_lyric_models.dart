import 'dart:convert';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/music_match_normalizer.dart';

enum ResultSource { qq, kugou, netease }

enum OnlineLyricFormat { lrc, krc, qrc }

class OnlineLyricPayload {
  final OnlineLyricFormat format;
  final String lyricText;
  final String? translationText;

  const OnlineLyricPayload(this.format, this.lyricText, [this.translationText]);
}

abstract interface class OnlineLyricProvider {
  ResultSource get source;

  Future<List<SongSearchResult>> search(String query, Audio audio);

  Future<OnlineLyricPayload?> fetch(SongSearchResult candidate);
}

class SongSearchResult {
  final ResultSource source;
  final String title;
  final String artists;
  final String album;
  final double score;
  final int? qqSongId;
  final String? neteaseSongId;
  final String? kugouSongHash;
  final int? durationSeconds;

  /// Score explanations are completed after a provider row is constructed.
  final List<String> matchReasons;

  SongSearchResult(
    this.source,
    this.title,
    this.artists,
    this.album,
    this.score, {
    this.qqSongId,
    this.neteaseSongId,
    this.kugouSongHash,
    this.durationSeconds,
    List<String>? matchReasons,
  }) : matchReasons = matchReasons ?? <String>[];

  @override
  String toString() => json.encode({
        'source': source.toString(),
        'title': title,
        'artists': artists,
        'album': album,
        'score': score,
      });

  static SongSearchResult fromQQSearchResult(Map itemSong, Audio audio) {
    final title = _requiredString(itemSong['name'], 'qq name');
    final artists = _artistNames(itemSong['singer'], 'qq singer');
    final albumMap = _requiredMap(itemSong['album'], 'qq album');
    final album = _requiredString(albumMap['title'], 'qq album title');
    final id = _intValue(itemSong['id']);
    if (id == null) throw const FormatException('qq id is missing');
    return _scored(
      ResultSource.qq,
      title,
      artists,
      album,
      audio,
      qqSongId: id,
      durationSeconds: _durationSeconds(itemSong['interval']),
    );
  }

  static SongSearchResult fromNeteaseSearchResult(Map song, Audio audio) {
    final title = _requiredString(song['name'], 'netease name');
    final artists = _artistNames(song['artists'], 'netease artists');
    final albumMap = _requiredMap(song['album'], 'netease album');
    final album = _requiredString(albumMap['name'], 'netease album name');
    final id = song['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('netease id is missing');
    }
    final milliseconds = _durationSeconds(song['duration'] ?? song['dt']);
    return _scored(
      ResultSource.netease,
      title,
      artists,
      album,
      audio,
      neteaseSongId: id,
      durationSeconds:
          milliseconds == null ? null : (milliseconds / 1000).round(),
    );
  }

  static SongSearchResult fromKugouSearchResult(Map info, Audio audio) {
    final title = _requiredString(info['songname'], 'kugou songname');
    final album = _requiredString(info['album_name'], 'kugou album_name');
    final artists = _requiredString(info['singername'], 'kugou singername');
    final hash = _requiredString(info['hash'], 'kugou hash');
    return _scored(
      ResultSource.kugou,
      title,
      artists,
      album,
      audio,
      kugouSongHash: hash,
      durationSeconds: _durationSeconds(info['duration'] ?? info['timelength']),
    );
  }

  static SongSearchResult _scored(
    ResultSource source,
    String title,
    String artists,
    String album,
    Audio audio, {
    int? qqSongId,
    String? neteaseSongId,
    String? kugouSongHash,
    int? durationSeconds,
  }) {
    final score = scoreMusicCandidate(
      audio,
      title: title,
      artists: artists,
      album: album,
      durationSeconds: durationSeconds,
    );
    return SongSearchResult(
      source,
      title,
      artists,
      album,
      score.value,
      qqSongId: qqSongId,
      neteaseSongId: neteaseSongId,
      kugouSongHash: kugouSongHash,
      durationSeconds: durationSeconds,
      matchReasons: score.reasons.toList(),
    );
  }
}

Map _requiredMap(Object? value, String field) {
  if (value is Map) return value;
  throw FormatException('$field is missing');
}

String _requiredString(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$field is missing');
}

String _artistNames(Object? value, String field) {
  if (value is! List) throw FormatException('$field is missing');
  final names = <String>[];
  for (final artist in value) {
    if (artist is! Map) throw FormatException('$field row is malformed');
    names.add(_requiredString(artist['name'], '$field name'));
  }
  if (names.isEmpty) throw FormatException('$field is empty');
  return names.join('、');
}

int? _intValue(Object? value) => switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };

int? _durationSeconds(Object? value) => _intValue(value);
