import 'dart:async';

import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_scroll_positioner.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VerticalLyricView extends StatefulWidget {
  const VerticalLyricView({super.key});

  @override
  State<VerticalLyricView> createState() => _VerticalLyricViewState();
}

class _VerticalLyricViewState extends State<VerticalLyricView> {
  bool isHovering = false;
  final lyricViewController = LyricViewController();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    const loadingWidget = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(),
      ),
    );

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          isHovering = true;
        });
      },
      onExit: (_) {
        setState(() {
          isHovering = false;
        });
      },
      child: Material(
        type: MaterialType.transparency,
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(scrollbars: false),
          child: ChangeNotifierProvider.value(
            value: lyricViewController,
            child: ListenableBuilder(
              listenable: lyricViewController,
              builder: (context, _) => ListenableBuilder(
                listenable: PlayService.instance.lyricService,
                builder: (context, _) => FutureBuilder(
                  future: PlayService.instance.lyricService.currLyricFuture,
                  builder: (context, snapshot) {
                    final lyricNullable = snapshot.data;
                    final noLyricWidget = Center(
                      child: Text(
                        "无歌词",
                        style: TextStyle(
                          fontSize: 22,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    );

                    return Stack(
                      children: [
                        switch (snapshot.connectionState) {
                          ConnectionState.none => loadingWidget,
                          ConnectionState.waiting => loadingWidget,
                          ConnectionState.active => loadingWidget,
                          ConnectionState.done => lyricNullable == null
                              ? noLyricWidget
                              : _VerticalLyricScrollView(lyric: lyricNullable),
                        },
                        if (isHovering ||
                            lyricViewController.keepControlsVisible)
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: LyricViewControls(),
                          )
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final LYRIC_VIEW_KEY = GlobalKey();

class _VerticalLyricScrollView extends StatefulWidget {
  const _VerticalLyricScrollView({required this.lyric});

  final Lyric lyric;

  @override
  State<_VerticalLyricScrollView> createState() =>
      _VerticalLyricScrollViewState();
}

class _VerticalLyricScrollViewState extends State<_VerticalLyricScrollView> {
  final playbackService = PlayService.instance.playbackService;
  final lyricService = PlayService.instance.lyricService;
  late StreamSubscription lyricLineStreamSubscription;
  final scrollController = ScrollController();
  LyricViewController? _lyricViewController;
  bool _centerScheduled = false;
  Size? _lastViewportSize;

  int _currentLine = 0;

  /// 用来定位到当前歌词
  final currentLyricTileKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _initLyricView();
    lyricLineStreamSubscription =
        lyricService.lyricLineStream.listen(_updateNextLyricLine);
  }

  @override
  void didUpdateWidget(covariant _VerticalLyricScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyric, widget.lyric)) _initLyricView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<LyricViewController>();
    if (identical(next, _lyricViewController)) return;
    _lyricViewController?.removeListener(_scheduleCurrentLyricCenter);
    _lyricViewController = next;
    _lyricViewController!.addListener(_scheduleCurrentLyricCenter);
  }

  void _scheduleCurrentLyricCenter({bool animate = true}) {
    if (_centerScheduled || !mounted) return;
    _centerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _centerScheduled = false;
      if (!mounted) return;
      await LyricScrollPositioner.center(
        currentLyricTileKey,
        animate: animate,
      );
    });
  }

  /// 加载当前歌词页面，获取并滚动到当前歌词行的位置
  void _initLyricView() {
    _currentLine = lyricLineIndexAt(
      widget.lyric.lines,
      Duration(
        microseconds:
            (playbackService.position * Duration.microsecondsPerSecond).round(),
      ),
      lyricService.lyricOffset,
    );
    _scheduleCurrentLyricCenter();
  }

  void _seekToLyricLine(int i) {
    final target = lyricDisplayStart(
      widget.lyric.lines[i].start,
      lyricService.lyricOffset,
    );
    playbackService.seek(target.inMilliseconds / 1000);
    setState(() {
      _currentLine = i;
    });
    _scheduleCurrentLyricCenter();
  }

  void _updateNextLyricLine(int lyricLine) {
    if (_currentLine != lyricLine) setState(() => _currentLine = lyricLine);

    _scheduleCurrentLyricCenter();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (nextSize.isFinite && nextSize != _lastViewportSize) {
          _lastViewportSize = nextSize;
          _scheduleCurrentLyricCenter(animate: false);
        }

        return CustomScrollView(
          key: LYRIC_VIEW_KEY,
          controller: scrollController,
          slivers: [
            const SliverFillRemaining(),
            SliverToBoxAdapter(
              child: LyricTileList(
                lyric: widget.lyric,
                currentLine: _currentLine,
                currentTileKey: currentLyricTileKey,
                onTap: _seekToLyricLine,
              ),
            ),
            const SliverFillRemaining(),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _lyricViewController?.removeListener(_scheduleCurrentLyricCenter);
    lyricLineStreamSubscription.cancel();
    scrollController.dispose();
    super.dispose();
  }
}

/// Retains unchanged row widgets when only the highlighted lyric line changes.
class LyricTileList extends StatefulWidget {
  const LyricTileList({
    super.key,
    required this.lyric,
    required this.currentLine,
    required this.currentTileKey,
    required this.onTap,
  });

  final Lyric lyric;
  final int currentLine;
  final GlobalKey currentTileKey;
  final ValueChanged<int> onTap;

  @override
  State<LyricTileList> createState() => _LyricTileListState();
}

class _LyricTileListState extends State<LyricTileList> {
  late List<LyricViewTile> _tiles;

  LyricViewTile _tile(int index) => LyricViewTile(
        key: index == widget.currentLine ? widget.currentTileKey : null,
        line: widget.lyric.lines[index],
        opacity: index == widget.currentLine ? 1 : .18,
        onTap: () => widget.onTap(index),
      );

  @override
  void initState() {
    super.initState();
    _tiles = List.generate(widget.lyric.lines.length, _tile);
  }

  @override
  void didUpdateWidget(covariant LyricTileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyric, widget.lyric) ||
        oldWidget.currentTileKey != widget.currentTileKey) {
      _tiles = List.generate(widget.lyric.lines.length, _tile);
    } else if (oldWidget.currentLine != widget.currentLine) {
      // A fresh child list is required by Flutter; reuse every unchanged widget.
      _tiles = List.of(_tiles);
      for (final index in [oldWidget.currentLine, widget.currentLine]) {
        if (index >= 0 && index < _tiles.length) _tiles[index] = _tile(index);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _tiles,
      );
}
