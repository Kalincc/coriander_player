import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/src/rust/api/system_theme.dart';
import 'package:coriander_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path) => Audio(
      path,
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'Lofty',
    );

void main() {
  setUpAll(() {
    RustLib.initMock(api: _TestRustLibApi());
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('hotkey_manager'), (_) async => null);
  });

  testWidgets('reads items and plays an index through an injected service',
      (tester) async {
    final first = _audio('D:/music/first.flac');
    final second = _audio('D:/music/second.flac');
    final playback = _FakePlaybackService([first, second], currentIndex: 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CurrentPlaylistView(playbackService: playback)),
    ));

    expect(find.text(first.title), findsOneWidget);
    expect(find.text(second.title), findsOneWidget);
    expect(find.byTooltip('Clear queue'), findsNothing);
    expect(find.byTooltip('Remove from queue'), findsNothing);
    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.tap(find.text(second.title));
    expect(playback.playedIndexes, [1]);
  });

  testWidgets('remove, clear, undo and reorder never request another playback',
      (tester) async {
    final songs = [_audio('a'), _audio('b'), _audio('c')];
    final playback = _FakePlaybackService(songs, currentIndex: 1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CurrentPlaylistView(playbackService: playback))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('remove-queue-1')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('remove-queue-0')));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [songs[1], songs[2]]);
    await tester.tap(find.byTooltip('撤销队列操作'));
    await tester.pumpAndSettle();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorder(2, 0);
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [songs[2], songs[0], songs[1]]);
    await tester.tap(find.byTooltip('清空待播，保留当前歌曲'));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [songs[1]]);
    expect(playback.playedIndexes, isEmpty);
  });

  testWidgets(
      'saving snapshots the queue and retries failures without changing playback',
      (tester) async {
    final songs = [_audio('a'), _audio('b')];
    final playback = _FakePlaybackService(songs, currentIndex: 0);
    var calls = 0;
    List<Audio>? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CurrentPlaylistView(
                playbackService: playback,
                saveAsPlaylist: (name, items) async {
                  calls++;
                  if (calls == 1) throw StateError('disk full');
                  saved = List.of(items);
                }))));
    await tester.tap(find.byTooltip('保存队列为歌单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新的歌单');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('重试保存'), findsOneWidget);
    playback.clearUpcomingQueue();
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(saved, songs);
    expect(calls, 2);
    expect(playback.playedIndexes, isEmpty);
  });

  testWidgets('manual browsing is retained until locate-current is requested',
      (tester) async {
    final playback = _FakePlaybackService(
        List.generate(40, (i) => _audio('song $i')),
        currentIndex: 0);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CurrentPlaylistView(playbackService: playback))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .scrollController!;
    final offset = controller.offset;
    playback.advanceTo(25);
    await tester.pumpAndSettle();
    expect(controller.offset, offset);
    await tester.tap(find.byTooltip('定位当前歌曲'));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(offset));
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

class _FakePlaybackService extends ChangeNotifier
    implements PlaybackPlaylistController {
  _FakePlaybackService(List<Audio> items, {required this.currentIndex})
      : playlist = ValueNotifier(List.unmodifiable(items)) {
    queue.play(currentIndex, items);
  }
  final queue = PlaybackPlaylistContext();

  @override
  final ValueNotifier<List<Audio>> playlist;

  final int currentIndex;

  final playedIndexes = <int>[];

  void advanceTo(int index) {
    queue.selectIndex(index);
    notifyListeners();
  }

  @override
  int get playlistIndex => queue.currentIndex;

  @override
  void playIndexOfPlaylist(int audioIndex) {
    playedIndexes.add(audioIndex);
  }

  @override
  Object queueItemKey(int index) => queue.itemKey(index);
  @override
  bool get canUndoQueueEdit => queue.canUndo;
  bool _publish(bool changed) {
    if (changed) {
      playlist.value = queue.items;
      notifyListeners();
    }
    return changed;
  }

  @override
  bool moveQueueItem(int oldIndex, int newIndex) =>
      _publish(queue.move(oldIndex, newIndex));
  @override
  bool removeQueueItem(int index) => _publish(queue.remove(index));
  @override
  bool clearUpcomingQueue() => _publish(queue.clearUpcoming());
  @override
  bool undoQueueEdit() => _publish(queue.undo());
}
