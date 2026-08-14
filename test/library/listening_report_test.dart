import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/listening_report.dart';
import 'package:coriander_player/library/playback_history_models.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

Audio makeAudio(String path, int index) => Audio(
      'Song $index',
      index.isEven ? 'Artist B' : 'Artist A',
      index.isEven ? 'Album B' : 'Album A',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

PlaybackHistoryEvent event(
  String path,
  DateTime startedAt, {
  int seconds = 30,
  bool qualified = true,
}) =>
    PlaybackHistoryEvent(
      path: path,
      startedAt: startedAt,
      listened: Duration(seconds: seconds),
      qualified: qualified,
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  test('uses Monday and month boundaries with an exclusive period end', () {
    final monday = DateTime(2026, 8, 3);
    final metadata = {
      'D:/music/inside.flac': makeAudio('D:/music/inside.flac', 1),
      'D:/music/end.flac': makeAudio('D:/music/end.flac', 2),
    };

    final report = buildListeningReport(
      [
        event('D:/music/inside.flac', monday),
        event('D:/music/end.flac', DateTime(2026, 8, 10)),
      ],
      ReportPeriod.currentWeek(DateTime(2026, 8, 5, 14)),
      metadata,
    );

    expect(ReportPeriod.currentWeek(DateTime(2026, 8, 5)).start, monday);
    expect(report.qualifiedPlayCount, 1);
    expect(report.songRanks.single.name, 'Song 1');
    expect(ReportPeriod.currentMonth(DateTime(2027, 1, 12)).start,
        DateTime(2027, 1));
  });

  test('keeps UTC clock basis for the recent twelve month boundary', () {
    final now = DateTime.utc(2026, 8, 5, 14, 30);

    final period = ReportPeriod.recentTwelveMonths(now);

    expect(period.start, DateTime.utc(2025, 8, 5));
    expect(period.end, DateTime.utc(2026, 8, 5, 14, 30, 0, 0, 1));
  });

  test('creates unique recent-history keys for repeated song events', () {
    final repeated = event(
      'D:/music/repeated.flac',
      DateTime.utc(2026, 8, 5, 14, 30),
    );

    expect(recentHistoryItemKey(repeated, 0),
        isNot(recentHistoryItemKey(repeated, 1)));
  });

  test('aggregates the top ten ranks by duration then plays then name', () {
    final metadata = <String, Audio>{};
    final events = <PlaybackHistoryEvent>[];
    final startedAt = DateTime(2026, 8, 11, 9);

    for (var index = 0; index < 11; index++) {
      final path = 'D:/music/$index.flac';
      metadata[path] = makeAudio(path, index);
      events.add(event(path, startedAt, seconds: 30));
    }
    events.add(event('D:/music/0.flac', startedAt, seconds: 40));
    events.add(event('D:/music/1.flac', startedAt, seconds: 30));
    events.add(event('D:/music/missing.flac', startedAt, seconds: 120));
    events.add(event('D:/music/2.flac', startedAt, qualified: false));

    final report = buildListeningReport(
      events,
      ReportPeriod.currentMonth(startedAt),
      metadata,
    );

    expect(report.totalListened, const Duration(seconds: 520));
    expect(report.qualifiedPlayCount, 14);
    expect(report.songRanks, hasLength(10));
    expect(report.songRanks.first, isA<ListeningRank>());
    expect(report.songRanks.first.name, 'D:/music/missing.flac');
    expect(report.songRanks.first.playCount, 1);
    expect(report.songRanks.first.listened, const Duration(seconds: 120));
    expect(report.songRanks[1].name, 'Song 0');
    expect(report.songRanks[2].name, 'Song 1');
    expect(report.songRanks.map((rank) => rank.name),
        contains('D:/music/missing.flac'));
    expect(report.songRanks.last.name, 'Song 7');
    expect(
        report.artistRanks.map((rank) => rank.name), ['Artist B', 'Artist A']);
    expect(report.albumRanks.map((rank) => rank.name), ['Album B', 'Album A']);
  });

  test('uses play count and name only to break duration ties', () {
    final startedAt = DateTime(2026, 8, 11, 9);
    Audio named(String path, String name) => Audio(
          name,
          '$name Artist',
          '$name Album',
          1,
          180,
          320,
          44100,
          path,
          1,
          1,
          'test',
        );
    final metadata = {
      'long': named('long', 'Long'),
      'frequent': named('frequent', 'Frequent'),
      'single': named('single', 'Single'),
      'alpha': named('alpha', 'Alpha'),
      'beta': named('beta', 'Beta'),
    };
    final report = buildListeningReport(
      [
        event('long', startedAt, seconds: 120),
        event('frequent', startedAt, seconds: 30),
        event('frequent', startedAt, seconds: 30),
        event('single', startedAt, seconds: 60),
        event('beta', startedAt, seconds: 30),
        event('alpha', startedAt, seconds: 30),
      ],
      ReportPeriod.currentMonth(startedAt),
      metadata,
    );

    expect(
      report.songRanks.map((rank) => rank.name),
      ['Long', 'Frequent', 'Single', 'Alpha', 'Beta'],
    );
    expect(report.artistRanks.first.name, 'Long Artist');
    expect(report.albumRanks.first.name, 'Long Album');
  });
}

class _TestRustLibApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(
        fore: (255, 0, 0, 0),
        accent: (255, 0, 0, 0),
      );
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
