import 'dart:async';

import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../music_matcher_test.dart'
    show FakeProvider, memoryCache, makeAudio, candidate;

void main() {
  setUpAll(() => RustLib.initMock(api: _TestRustLibApi()));
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('hotkey_manager'), (_) async => null);
  });

  testWidgets(
      'fast candidates remain visible while another source searches and retries',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final slow = Completer<List<SongSearchResult>>();
    var slowCalls = 0;
    final audio = makeAudio('widget-progress.flac', 1);
    final search = OnlineLyricSearchController(
        audio: audio,
        cache: memoryCache(),
        providers: [
          FakeProvider(ResultSource.qq,
              search: (_, __) async =>
                  [candidate(ResultSource.qq, '红豆', '王菲', '唱游', id: 1)]),
          FakeProvider(ResultSource.netease, search: (_, __) {
            slowCalls++;
            return slow.future;
          }),
        ]);
    addTearDown(search.dispose);
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    unawaited(showLyricSourceDialog(
        navigator: navigator.currentState!,
        audio: audio,
        searchController: search));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('QQ音乐：找到 1 条候选'), findsOneWidget);
    expect(find.text('网易云音乐：搜索中…'), findsOneWidget);
    expect(
        find.descendant(of: find.byType(ListTile), matching: find.text('红豆')),
        findsOneWidget);
    await tester.tap(find.byTooltip('重试QQ音乐'));
    await tester.pump();
    expect(slowCalls, 1);
    slow.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('网易云音乐：无有效结果'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'manual query works at narrow widths without changing original metadata',
      (tester) async {
    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    final audio = makeAudio('manual-widget.flac', 1);
    final queries = <String>[];
    final search = OnlineLyricSearchController(
        audio: audio,
        cache: memoryCache(),
        providers: [
          FakeProvider(ResultSource.qq, search: (query, _) async {
            queries.add(query);
            return [];
          }),
          FakeProvider(ResultSource.kugou, search: (_, __) async => []),
          FakeProvider(ResultSource.netease, search: (_, __) async {
            throw StateError('network unavailable');
          }),
        ]);
    addTearDown(search.dispose);
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    unawaited(showLyricSourceDialog(
        navigator: navigator.currentState!,
        audio: audio,
        searchController: search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lyric-search-title')), '遇见');
    await tester.enterText(find.byKey(const Key('lyric-search-artist')), '孙燕姿');
    await tester.tap(find.byTooltip('重新搜索歌词'));
    await tester.pumpAndSettle();
    expect(
        queries.any((query) => query.contains('遇见') && query.contains('孙燕姿')),
        isTrue);
    expect(audio.title, '红豆');
    expect(audio.artist, '王菲');
    final count = queries.length;
    await tester.enterText(find.byKey(const Key('lyric-search-title')), ' ');
    await tester.tap(find.byTooltip('重新搜索歌词'));
    await tester.pumpAndSettle();
    expect(find.text('请填写歌曲标题'), findsOneWidget);
    expect(queries.length, count);
    expect(tester.takeException(), isNull);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('theme changes keep the same lyric search request',
      (tester) async {
    var searches = 0;
    final navigatorKey = GlobalKey<NavigatorState>();
    final mode = ValueNotifier(ThemeMode.light);
    final audio =
        Audio('红豆', '王菲', '唱游', 0, 240, null, null, 'song', 0, 0, null);
    final search = OnlineLyricSearchController(
        audio: audio,
        cache: memoryCache(),
        providers: [
          FakeProvider(ResultSource.qq, search: (_, __) async {
            searches++;
            return [];
          })
        ]);
    addTearDown(search.dispose);
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
      audio: audio,
      searchController: search,
    ));
    await tester.pumpAndSettle();
    final initialSearches = searches;
    expect(initialSearches, greaterThan(0));
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(searches, initialSearches);
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
            final search = OnlineLyricSearchController(
                audio: widget.audio, cache: memoryCache(), providers: []);
            unawaited(showLyricSourceDialog(
              navigator: widget.navigatorKey.currentState!,
              audio: widget.audio,
              searchController: search,
            ).whenComplete(search.dispose));
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
