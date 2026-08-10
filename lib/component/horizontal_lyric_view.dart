import 'dart:async';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_presentation.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';

String horizontalLyricText(
  LyricLine line, {
  required bool showTranslation,
}) {
  final presentation = presentLyricLine(
    line,
    showTranslation: showTranslation,
  );
  final translation = presentation.translation;
  return translation == null
      ? presentation.primary
      : '${presentation.primary}┃$translation';
}

Duration horizontalLyricScrollDuration(
  LyricLine line, {
  required Duration waitFor,
}) {
  final length = switch (line) {
    LrcLine() => line.length,
    SyncLyricLine() => line.length,
    _ => Duration.zero,
  };
  return length - waitFor - waitFor;
}

class HorizontalLyricView extends StatelessWidget {
  const HorizontalLyricView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: ListenableBuilder(
        listenable: PlayService.instance.lyricService,
        builder: (context, _) => FutureBuilder(
          future: PlayService.instance.lyricService.currLyricFuture,
          builder: (context, snapshot) {
            if (snapshot.data == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Enjoy Music",
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              );
            }

            return _LyricHorizontalScrollArea(snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _LyricHorizontalScrollArea extends StatefulWidget {
  const _LyricHorizontalScrollArea(this.lyric);

  final Lyric lyric;

  @override
  State<_LyricHorizontalScrollArea> createState() =>
      _LyricHorizontalScrollAreaState();
}

class _LyricHorizontalScrollAreaState
    extends State<_LyricHorizontalScrollArea> {
  /// 停留300ms后启动，提前300ms滚动到底
  final waitFor = const Duration(milliseconds: 300);
  final scrollController = ScrollController();
  final lyricService = PlayService.instance.lyricService;
  final nowPlayingPagePreference = AppPreference.instance.nowPlayingPagePref;
  late StreamSubscription lyricLineStreamSubscription;

  var currContent = "Enjoy Music";
  var currentLine = 0;

  @override
  void initState() {
    super.initState();
    if (widget.lyric.lines.isNotEmpty) {
      currContent = horizontalLyricText(
        widget.lyric.lines.first,
        showTranslation: nowPlayingPagePreference.showTranslation,
      );
    }
    nowPlayingPagePreference.addListener(_refreshTranslation);

    lyricLineStreamSubscription = lyricService.lyricLineStream.listen((line) {
      if (line < 0 || line >= widget.lyric.lines.length) return;
      final currLine = widget.lyric.lines[line];

      setState(() {
        currentLine = line;
        currContent = horizontalLyricText(
          currLine,
          showTranslation: nowPlayingPagePreference.showTranslation,
        );
      });

      /// 减去启动延时和滚动结束停留时间
      final lastTime = horizontalLyricScrollDuration(
        currLine,
        waitFor: waitFor,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;

        scrollController.jumpTo(0);
        if (scrollController.position.maxScrollExtent > 0) {
          if (lastTime.isNegative) return;

          Future.delayed(waitFor, () {
            if (!scrollController.hasClients) return;

            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: lastTime,
              curve: Curves.linear,
            );
          });
        }
      });
    });
  }

  void _refreshTranslation() {
    if (!mounted || widget.lyric.lines.isEmpty) return;
    setState(() {
      currContent = horizontalLyricText(
        widget.lyric.lines[currentLine],
        showTranslation: nowPlayingPagePreference.showTranslation,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            currContent,
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    nowPlayingPagePreference.removeListener(_refreshTranslation);
    lyricLineStreamSubscription.cancel();
    scrollController.dispose();
    super.dispose();
  }
}
