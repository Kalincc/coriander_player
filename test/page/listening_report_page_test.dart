import 'dart:io';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/component/side_nav.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/page/listening_report_page.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('listening-report-test');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  testWidgets(
    'shows the current week summary, Top 10 sections, and a selected period',
    (tester) async {
      final now = DateTime(2026, 8, 5, 14);
      final audio = _audio(path: 'D:/music/weekly.flac', title: 'Weekly song');
      final history = await _historyWithQualifiedPlay(
        directory,
        audio,
        now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ListeningReportPage(
            historyService: history,
            audios: [audio],
            now: () => now,
          ),
        ),
      );

      expect(find.text('听歌报告'), findsOneWidget);
      expect(find.text('本周'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('近12个月'), findsOneWidget);
      expect(find.text('总听歌时长'), findsOneWidget);
      expect(find.text('有效播放'), findsOneWidget);
      expect(find.text('歌曲 Top 10'), findsOneWidget);
      expect(find.text('歌手 Top 10'), findsOneWidget);
      expect(find.text('专辑 Top 10'), findsOneWidget);
      expect(find.text('Weekly song'), findsOneWidget);

      await tester.tap(find.text('本月'));
      await tester.pump();

      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '本月'))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('uses a path fallback when report metadata is unavailable',
      (tester) async {
    final now = DateTime(2026, 8, 5, 14);
    final audio = _audio(path: 'D:/music/missing.flac', title: 'Missing song');
    final history = await _historyWithQualifiedPlay(
      directory,
      audio,
      now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ListeningReportPage(
          historyService: history,
          audios: const [],
          now: () => now,
        ),
      ),
    );

    expect(find.text('D:/music/missing.flac'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'D:/music/missing.flac'),
          )
          .onTap,
      isNull,
    );
  });

  testWidgets('shows no data for this week then rebuilds for this month',
      (tester) async {
    final now = DateTime(2026, 8, 5, 14);
    final audio = _audio(path: 'D:/music/month.flac', title: 'Month-only song');
    final history = await _historyWithQualifiedPlay(
      directory,
      audio,
      DateTime(2026, 8, 1, 14),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ListeningReportPage(
          historyService: history,
          audios: [audio],
          now: () => now,
        ),
      ),
    );

    expect(find.text('这个周期还没有有效播放记录'), findsOneWidget);
    expect(find.text('Month-only song'), findsNothing);

    await tester.tap(find.text('本月'));
    await tester.pump();

    expect(find.text('这个周期还没有有效播放记录'), findsNothing);
    expect(find.text('Month-only song'), findsOneWidget);
    expect(find.text('1 次'), findsOneWidget);
  });

  testWidgets('renders only ten song ranks when more songs are available',
      (tester) async {
    final now = DateTime(2026, 8, 5, 14);
    final audios = List.generate(
      11,
      (index) => _audio(
        path: 'D:/music/$index.flac',
        title: 'Song $index',
      ),
    );
    final history = await _historyWithQualifiedPlays(
      directory,
      [
        for (final audio in audios.take(10)) ...[audio, audio],
        audios.last,
      ],
      now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ListeningReportPage(
          historyService: history,
          audios: audios,
          now: () => now,
        ),
      ),
    );

    for (var index = 0; index < 10; index++) {
      expect(find.text('Song $index'), findsOneWidget);
    }
    expect(find.text('Song 10'), findsNothing);
  });

  testWidgets('uses injected metadata for artist and album detail targets',
      (tester) async {
    final now = DateTime(2026, 8, 5, 14);
    final audio = _audio(path: 'D:/music/detail.flac', title: 'Detail song');
    final history = await _historyWithQualifiedPlay(directory, audio, now);

    await tester.pumpWidget(
      MaterialApp(
        home: ListeningReportPage(
          historyService: history,
          audios: [audio],
          now: () => now,
        ),
      ),
    );

    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Test artist'))
          .onTap,
      isNotNull,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Test album'))
          .onTap,
      isNotNull,
    );
  });

  testWidgets('shows an unavailable state before playback history is loaded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ListeningReportPage()),
    );

    expect(find.text('听歌报告暂不可用'), findsOneWidget);
  });

  test('keeps the report in navigation but out of startup choices', () {
    final destination = destinations.singleWhere(
      (item) => item.desPath == app_paths.LISTENING_REPORT_PAGE,
    );

    expect(destination.label, '听歌报告');
    expect(destination.desPath, '/reports');
    expect(app_paths.START_PAGES, isNot(contains('/reports')));
  });
}

Future<PlaybackHistoryService> _historyWithQualifiedPlay(
  Directory directory,
  Audio audio,
  DateTime now,
) async {
  return _historyWithQualifiedPlays(directory, [audio], now);
}

Future<PlaybackHistoryService> _historyWithQualifiedPlays(
  Directory directory,
  Iterable<Audio> audios,
  DateTime now,
) async {
  final history = PlaybackHistoryService(
    store: LocalJsonStore(directory),
    now: () => now,
  );
  for (final audio in audios) {
    history.startSession(audio, startedAt: now);
    history.recordPosition(const Duration(seconds: 30));
    await history.endSession();
  }
  return history;
}

Audio _audio({required String path, required String title}) => Audio(
      title,
      'Test artist',
      'Test album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

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
