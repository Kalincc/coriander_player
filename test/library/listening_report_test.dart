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

  test('aggregates the top ten ranks by plays then duration then name', () {
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
    expect(report.songRanks.first.name, 'Song 0');
    expect(report.songRanks.first.playCount, 2);
    expect(report.songRanks.first.listened, const Duration(seconds: 70));
    expect(report.songRanks[1].name, 'Song 1');
    expect(report.songRanks.last.name, 'Song 8');
    expect(
        report.artistRanks.map((rank) => rank.name), ['Artist B', 'Artist A']);
    expect(report.albumRanks.map((rank) => rank.name), ['Album B', 'Album A']);
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
