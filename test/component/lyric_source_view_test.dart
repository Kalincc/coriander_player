import 'dart:async';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/online_lyric_models.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));

  testWidgets('theme changes keep the same lyric search request',
      (tester) async {
    var searches = 0;
    final navigatorKey = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (_, value, __) => MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: value,
          home: const SizedBox()),
    ));
    unawaited(showLyricSourceDialog(
      navigator: navigatorKey.currentState!,
      audio: Audio('', '', '', 0, 0, null, null, 'song', 0, 0, null),
      search: (_) async {
        searches++;
        return const OnlineLyricSearchReport(candidates: [], statuses: []);
      },
    ));
    await tester.pumpAndSettle();
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(searches, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    mode.dispose();
  });

  testWidgets(
      'opens the lyric source dialog after the transient controls unmount',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final audio = Audio('', '', '', 0, 0, null, null, 'diagnostic', 0, 0, null);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: _TransientLyricSourceLauncher(
        navigatorKey: navigatorKey,
        audio: audio,
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('选择歌词源'), findsOneWidget);
    navigatorKey.currentState!.pop();
  });

  test('selects the source preview line using the lyric clock position', () {
    final lyric = Lrc(
      [
        LrcLine(Duration.zero, 'first', isBlank: false),
        LrcLine(const Duration(seconds: 1), 'second', isBlank: false),
      ],
      LrcSource.web,
    );

    final line = lyricSourcePreviewLine(
      lyric,
      const Duration(milliseconds: 1050),
      const Duration(milliseconds: 100),
    );

    expect(line, isA<LrcLine>());
    expect((line as LrcLine).content, 'first');
  });

  test('source preview hides translations through lyric presentation', () {
    final line = LrcLine(
      Duration.zero,
      'primary┃translation┃continued',
      isBlank: false,
    );

    expect(
      lyricSourcePreviewText(line, showTranslation: true),
      '当前：primary┃translation┃continued',
    );
    expect(
      lyricSourcePreviewText(line, showTranslation: false),
      '当前：primary',
    );
  });

  test('match summary contains source, score, and reasons', () {
    final result = SongSearchResult(
      ResultSource.qq,
      '红豆',
      '王菲',
      '唱游',
      .9,
      qqSongId: 1,
      matchReasons: const ['标题一致', '歌手一致'],
    );

    final summary = lyricSourceMatchSummary(result);

    expect(summary, contains('QQ音乐'));
    expect(summary, contains('90%'));
    expect(summary, contains('标题一致'));
    expect(summary, contains('歌手一致'));
  });

  test('provider status label explains empty and failed searches', () {
    expect(
      lyricProviderStatusText(const LyricProviderSearchStatus(
        source: ResultSource.qq,
        state: LyricProviderSearchState.noResults,
        candidateCount: 0,
      )),
      'QQ音乐：无有效结果',
    );
    expect(
      lyricProviderStatusText(const LyricProviderSearchStatus(
        source: ResultSource.kugou,
        state: LyricProviderSearchState.failed,
        candidateCount: 0,
        errorMessage: '请求超时',
      )),
      contains('请求超时'),
    );
  });

  test('match summary marks cached lyric candidates', () {
    final result = SongSearchResult(
      ResultSource.qq,
      '红豆',
      '王菲',
      '唱游',
      .95,
      qqSongId: 1,
      fromCache: true,
    );

    expect(lyricSourceMatchSummary(result), contains('已缓存'));
  });
}

class _TransientLyricSourceLauncher extends StatefulWidget {
  const _TransientLyricSourceLauncher({
    required this.navigatorKey,
    required this.audio,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Audio audio;

  @override
  State<_TransientLyricSourceLauncher> createState() =>
      _TransientLyricSourceLauncherState();
}

class _TransientLyricSourceLauncherState
    extends State<_TransientLyricSourceLauncher> {
  var mountedControl = true;

  @override
  Widget build(BuildContext context) {
    if (!mountedControl) return const SizedBox.shrink();
    return Builder(
      builder: (_) => TextButton(
        onPressed: () {
          setState(() => mountedControl = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(showLyricSourceDialog(
              navigator: widget.navigatorKey.currentState!,
              audio: widget.audio,
              search: (_) async => const OnlineLyricSearchReport(
                candidates: [],
                statuses: [],
              ),
            ));
          });
        },
        child: const Text('打开'),
      ),
    );
  }
}

class _TestRustLibApi implements RustLibApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName ==
        #crateApiSystemThemeSystemThemeGetSystemTheme) {
      return const SystemTheme(fore: (255, 0, 0, 0), accent: (255, 0, 0, 0));
    }
    throw UnimplementedError(invocation.memberName.toString());
  }
}
