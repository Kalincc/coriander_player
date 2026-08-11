import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/playback_history_models.dart';

class ReportPeriod {
  ReportPeriod({required this.start, required this.end})
      : assert(end.isAfter(start));

  final DateTime start;
  final DateTime end;

  factory ReportPeriod.currentWeek(DateTime now) {
    final start = _calendarDate(
      now,
      now.year,
      now.month,
      now.day - now.weekday + DateTime.monday,
    );
    return ReportPeriod(start: start, end: start.add(const Duration(days: 7)));
  }

  factory ReportPeriod.currentMonth(DateTime now) {
    final start = _calendarDate(now, now.year, now.month, 1);
    return ReportPeriod(
        start: start, end: _calendarDate(now, now.year, now.month + 1, 1));
  }

  factory ReportPeriod.range(DateTime start, DateTime end) =>
      ReportPeriod(start: start, end: end);

  bool contains(DateTime timestamp) =>
      !timestamp.isBefore(start) && timestamp.isBefore(end);
}

class ListeningRank {
  const ListeningRank({
    required this.key,
    required this.name,
    required this.playCount,
    required this.listened,
  });

  final String key;
  final String name;
  final int playCount;
  final Duration listened;
}

class ListeningReport {
  const ListeningReport({
    required this.totalListened,
    required this.qualifiedPlayCount,
    required this.songCount,
    required this.artistCount,
    required this.albumCount,
    required this.songRanks,
    required this.artistRanks,
    required this.albumRanks,
  });

  final Duration totalListened;
  final int qualifiedPlayCount;
  final int songCount;
  final int artistCount;
  final int albumCount;
  final List<ListeningRank> songRanks;
  final List<ListeningRank> artistRanks;
  final List<ListeningRank> albumRanks;
}

ListeningReport buildListeningReport(
  Iterable<PlaybackHistoryEvent> events,
  ReportPeriod period,
  Map<String, Audio> metadata,
) {
  final songs = <String, _RankTotal>{};
  final artists = <String, _RankTotal>{};
  final albums = <String, _RankTotal>{};
  var totalListened = Duration.zero;
  var qualifiedPlayCount = 0;

  for (final event in events) {
    if (!event.qualified || !period.contains(event.startedAt)) continue;

    totalListened += event.listened;
    qualifiedPlayCount += 1;
    final audio = metadata[event.path];
    if (audio == null) continue;

    _add(songs, event.path, audio.title, event.listened);
    _add(artists, audio.artist, audio.artist, event.listened);
    _add(albums, audio.album, audio.album, event.listened);
  }

  return ListeningReport(
    totalListened: totalListened,
    qualifiedPlayCount: qualifiedPlayCount,
    songCount: songs.length,
    artistCount: artists.length,
    albumCount: albums.length,
    songRanks: _topTen(songs.values),
    artistRanks: _topTen(artists.values),
    albumRanks: _topTen(albums.values),
  );
}

void _add(
  Map<String, _RankTotal> totals,
  String key,
  String name,
  Duration listened,
) {
  final total = totals.putIfAbsent(key, () => _RankTotal(key, name));
  total.playCount += 1;
  total.listened += listened;
}

List<ListeningRank> _topTen(Iterable<_RankTotal> totals) {
  final ranks = totals
      .map(
        (total) => ListeningRank(
          key: total.key,
          name: total.name,
          playCount: total.playCount,
          listened: total.listened,
        ),
      )
      .toList()
    ..sort((a, b) {
      final byPlays = b.playCount.compareTo(a.playCount);
      if (byPlays != 0) return byPlays;
      final byDuration = b.listened.compareTo(a.listened);
      if (byDuration != 0) return byDuration;
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      return a.key.compareTo(b.key);
    });
  return List.unmodifiable(ranks.take(10));
}

class _RankTotal {
  _RankTotal(this.key, this.name);

  final String key;
  final String name;
  var playCount = 0;
  var listened = Duration.zero;
}

DateTime _calendarDate(DateTime source, int year, int month, int day) =>
    source.isUtc ? DateTime.utc(year, month, day) : DateTime(year, month, day);
