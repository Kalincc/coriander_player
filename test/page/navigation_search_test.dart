import 'package:coriander_player/app_paths.dart' as paths;
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/app_shell.dart';
import 'package:coriander_player/component/side_nav.dart';
import 'package:coriander_player/entry.dart';
import 'package:coriander_player/page/search_page/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
      'restores the prior start page without retaining the folders destination',
      () {
    expect(paths.restoreStartPage(null, 3), paths.AUDIOS_PAGE);
    expect(paths.restoreStartPage(null, 4), paths.PLAYLISTS_PAGE);
    expect(paths.restoreStartPage(paths.ALBUMS_PAGE, 4), paths.ALBUMS_PAGE);
    expect(paths.restoreStartPage(null, 'invalid'), paths.AUDIOS_PAGE);
    expect(destinations.map((item) => item.label), isNot(contains('文件夹')));
  });

  testWidgets('production branch order matches the sidebar', (tester) async {
    final router = Entry(welcome: true).config;
    addTearDown(router.dispose);
    final shell =
        router.configuration.routes.whereType<StatefulShellRoute>().single;
    expect(
        shell.branches.map((branch) => (branch.routes.single as GoRoute).path),
        destinations.map((destination) => destination.desPath));
  });

  test('recent searches are trimmed, deduplicated and capped', () {
    final preferences = AppPreference();
    for (var i = 0; i < 9; i++) {
      preferences.rememberSearch('Song $i');
    }
    preferences.rememberSearch('  song 7 ');
    preferences.rememberSearch(' ');
    expect(preferences.recentSearches.value, hasLength(8));
    expect(preferences.recentSearches.value.take(2), ['song 7', 'Song 8']);
    expect(
        preferences.recentSearches.value
            .where((s) => s.toLowerCase() == 'song 7'),
        hasLength(1));
  });

  testWidgets('Ctrl+F and the title button preserve search and album state',
      (tester) async {
    tester.view.physicalSize = const Size(507, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), (_) async => false);
    messenger.setMockMethodCallHandler(
        const MethodChannel('hotkey_manager'), (_) async => null);
    final prefs = AppPreference.instance;
    final oldQueries = prefs.recentSearches.value;
    final oldPage = prefs.startPage;
    prefs.recentSearches.value = const [];
    addTearDown(() {
      prefs.recentSearches.value = oldQueries;
      prefs.startPage = oldPage;
    });
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final router = GoRouter(
      initialLocation: paths.ALBUMS_PAGE,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, navigation) => AppShell(
            navigation: navigation,
            nowPlaying: const SizedBox.shrink(),
          ),
          branches: [
            for (final destination in destinations)
              StatefulShellBranch(routes: [
                GoRoute(
                  path: destination.desPath,
                  builder: (_, __) => switch (destination.desPath) {
                    paths.ALBUMS_PAGE => _BrowsePage(scroll),
                    paths.SEARCH_PAGE => const SearchPage(),
                    _ => const SizedBox.shrink(),
                  },
                  routes: [
                    if (destination.desPath == paths.AUDIOS_PAGE)
                      GoRoute(
                        path: 'detail',
                        builder: (_, __) => const Material(child: Text('歌曲详情')),
                      ),
                    if (destination.desPath == paths.SEARCH_PAGE)
                      GoRoute(
                        path: 'result',
                        builder: (context, state) => Material(
                          child: Column(children: [
                            Text('Result: ${state.extra}'),
                            TextButton(
                              onPressed: () =>
                                  context.push(paths.AUDIO_DETAIL_PAGE),
                              child: const Text('打开歌曲详情'),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
              ]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换筛选'));
    scroll.jumpTo(400);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final input = find.byType(TextField);
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    await tester.enterText(input, '红豆');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Result: 红豆'), findsOneWidget);
    expect(prefs.recentSearches.value, ['红豆']);
    await tester.tap(find.text('打开歌曲详情'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲详情'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Result: 红豆'), findsOneWidget);

    await tester.tap(find.byTooltip('打开导航栏'));
    await tester.pumpAndSettle();
    expect(find.text('文件夹'), findsNothing);
    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();
    expect(find.text('筛选已应用'), findsOneWidget);
    expect(scroll.offset, 400);
    await tester.tap(find.byTooltip('搜索 (Ctrl+F)'));
    await tester.pumpAndSettle();
    expect(find.text('Result: 红豆'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '红豆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _BrowsePage extends StatefulWidget {
  const _BrowsePage(this.scroll);
  final ScrollController scroll;

  @override
  State<_BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<_BrowsePage> {
  var filtered = false;

  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(
          onPressed: () => setState(() => filtered = true),
          child: Text(filtered ? '筛选已应用' : '切换筛选'),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: 40,
            itemExtent: 60,
            itemBuilder: (_, i) => Text('Album $i'),
          ),
        ),
      ]);
}
