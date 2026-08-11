import 'dart:io';

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
  });

  testWidgets('shows an unavailable state before playback history is loaded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ListeningReportPage()),
    );

    expect(find.text('听歌报告暂不可用'), findsOneWidget);
  });
}

Future<PlaybackHistoryService> _historyWithQualifiedPlay(
  Directory directory,
  Audio audio,
  DateTime now,
) async {
  final history = PlaybackHistoryService(
    store: LocalJsonStore(directory),
    now: () => now,
  );
  history.startSession(audio, startedAt: now);
  history.recordPosition(const Duration(seconds: 30));
  await history.endSession();
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
