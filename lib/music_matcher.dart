import 'dart:convert';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/krc.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/qrc.dart';
import 'package:coriander_player/lyric/music_match_normalizer.dart';
import 'package:coriander_player/utils.dart';
import 'package:music_api/music_api.dart';

enum ResultSource { qq, kugou, netease }

double _computeScore(
  Audio audio,
  String title,
  String artists,
  String album, {
  int? durationSeconds,
}) =>
    scoreMusicCandidate(
      audio,
      title: title,
      artists: artists,
      album: album,
      durationSeconds: durationSeconds,
    ).value;

class SongSearchResult {
  ResultSource source;
  String title;
  String artists;
  String album;
  double score;

  /// for qq result
  int? qqSongId;

  /// for netease result
  String? neteaseSongId;

  /// for kugou result
  String? kugouSongHash;

  SongSearchResult(
      this.source, this.title, this.artists, this.album, this.score,
      {this.qqSongId, this.neteaseSongId, this.kugouSongHash});

  @override
  String toString() {
    return json.encode({
      "source": source.toString(),
      "title": title,
      "artists": artists,
      "album": album,
      "score": score,
    });
  }

  static SongSearchResult fromQQSearchResult(Map itemSong, Audio audio) {
    final List singer = itemSong["singer"];
    final buffer = StringBuffer(singer.first["name"]);
    for (int i = 1; i < singer.length; ++i) {
      buffer.write("、${singer[i]["name"]}");
    }

    final title = itemSong["name"] ?? "";
    final album = itemSong["album"]["title"] ?? "";
    final artists = buffer.toString();

    return SongSearchResult(
      ResultSource.qq,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album,
          durationSeconds:
              itemSong["interval"] is int ? itemSong["interval"] : null),
      qqSongId: itemSong["id"],
    );
  }

  static SongSearchResult fromNeteaseSearchResult(Map song, Audio audio) {
    final title = song["name"] ?? "";

    final List artistList = song["artists"];
    final buffer = StringBuffer(artistList.first["name"]);
    for (int i = 1; i < artistList.length; ++i) {
      buffer.write("、${artistList[i]["name"]}");
    }
    final artists = buffer.toString();

    final album = song["album"]["name"] ?? "";

    return SongSearchResult(
      ResultSource.netease,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album,
          // NetEase's `duration` field is milliseconds; scorer expects seconds.
          durationSeconds: song["duration"] is int
              ? ((song["duration"] as int) / 1000).round()
              : null),
      neteaseSongId: song["id"].toString(),
    );
  }

  static SongSearchResult fromKugouSearchResult(Map info, Audio audio) {
    final title = info["songname"];
    final album = info["album_name"];
    final artists = info["singername"];

    return SongSearchResult(
      ResultSource.kugou,
      title,
      artists,
      album,
      _computeScore(audio, title, artists, album,
          durationSeconds: info["duration"] is int ? info["duration"] : null),
      kugouSongHash: info["hash"],
    );
  }
}

Future<List<SongSearchResult>> uniSearch(Audio audio) async {
  final queries = musicSearchQueriesFor(audio);
  final query = queries.isEmpty ? audio.title : queries.first;
  try {
    List<SongSearchResult> result = [];

    final Map kugouAnswer = (await KuGou.searchSong(keyword: query)).data;
    final List kugouResultList = kugouAnswer["data"]["info"];
    for (int j = 0; j < kugouResultList.length; j++) {
      if (j >= 5) break;
      result.add(SongSearchResult.fromKugouSearchResult(
        kugouResultList[j],
        audio,
      ));
    }

    final Map neteaseAnswer = (await Netease.search(keyWord: query)).data;
    final List neteaseResultList = neteaseAnswer["result"]["songs"];
    for (int k = 0; k < neteaseResultList.length; k++) {
      if (k >= 5) break;
      result.add(SongSearchResult.fromNeteaseSearchResult(
        neteaseResultList[k],
        audio,
      ));
    }

    final Map qqAnswer = (await QQ.search(keyWord: query)).data;
    final List qqResultList = qqAnswer["req"]["data"]["body"]["item_song"];
    for (int i = 0; i < qqResultList.length; i++) {
      if (i >= 5) break;
      result.add(SongSearchResult.fromQQSearchResult(
        qqResultList[i],
        audio,
      ));
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  } catch (err, trace) {
    LOGGER.e("query: $query");
    LOGGER.e(err, stackTrace: trace);
  }
  return Future.value([]);
}

Future<Lrc?> _getNeteaseUnsyncLyric(String neteaseSongId) async {
  try {
    final answer = await Netease.lyric(id: neteaseSongId);
    final lrcText = answer.data["lrc"]["lyric"];
    if (lrcText is String) {
      final lrcTrans = answer.data["tlyric"]["lyric"];
      return Lrc.fromLrcText(
        lrcText + lrcTrans,
        LrcSource.web,
        separator: "┃",
      );
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Qrc?> _getQQSyncLyric(int qqSongId) async {
  try {
    final answer = await QQ.songLyric3(songId: qqSongId);
    final qrcText = answer.data["lyric"];
    if (qrcText is String) {
      final qrcTransRawStr = answer.data["trans"];
      if (qrcTransRawStr is String) {
        return Qrc.fromQrcText(qrcText, qrcTransRawStr);
      }
      return Qrc.fromQrcText(qrcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Krc?> _getKugouSyncLyric(String kugouSongHash) async {
  try {
    final answer = await KuGou.krc(hash: kugouSongHash);
    final krcText = answer.data["lyric"];
    if (krcText is String) {
      return Krc.fromKrcText(krcText);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  return null;
}

Future<Lyric?> getOnlineLyric({
  int? qqSongId,
  String? kugouSongHash,
  String? neteaseSongId,
}) async {
  Lyric? lyric;
  if (qqSongId != null) {
    lyric = (await _getQQSyncLyric(qqSongId));
  } else if (kugouSongHash != null) {
    lyric = (await _getKugouSyncLyric(kugouSongHash));
  } else if (neteaseSongId != null) {
    lyric = await _getNeteaseUnsyncLyric(neteaseSongId);
  }
  return lyric;
}

Future<Lyric?> getMostMatchedLyric(Audio audio) async {
  final unisearchResult = await uniSearch(audio);
  if (unisearchResult.isEmpty) return null;

  final mostMatch = unisearchResult.first;

  return switch (mostMatch.source) {
    ResultSource.qq => getOnlineLyric(qqSongId: mostMatch.qqSongId),
    ResultSource.kugou =>
      getOnlineLyric(kugouSongHash: mostMatch.kugouSongHash),
    ResultSource.netease =>
      getOnlineLyric(neteaseSongId: mostMatch.neteaseSongId),
  };
}
