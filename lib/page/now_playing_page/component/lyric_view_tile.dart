import 'dart:async';
import 'dart:math';

import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_presentation.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricViewTile extends StatelessWidget {
  const LyricViewTile(
      {super.key, required this.line, required this.opacity, this.onTap});

  final LyricLine line;
  final double opacity;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final lyricViewController = context.watch<LyricViewController>();
    return Align(
      alignment: switch (lyricViewController.lyricTextAlign) {
        LyricTextAlign.left => Alignment.centerLeft,
        LyricTextAlign.center => Alignment.center,
        LyricTextAlign.right => Alignment.centerRight,
      },
      child: Opacity(
        opacity: opacity,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.0),
          child: line is SyncLyricLine
              ? _SyncLineContent(
                  syncLine: line as SyncLyricLine,
                  isMainLine: opacity == 1.0,
                )
              : _LrcLineContent(
                  lrcLine: line as LrcLine,
                  isMainLine: opacity == 1.0,
                ),
        ),
      ),
    );
  }
}

class _SyncLineContent extends StatelessWidget {
  const _SyncLineContent({required this.syncLine, required this.isMainLine});

  final SyncLyricLine syncLine;
  final bool isMainLine;

  @override
  Widget build(BuildContext context) {
    if (syncLine.words.isEmpty) {
      if (syncLine.length > const Duration(seconds: 5) && isMainLine) {
        return LyricTransitionTile(syncLine: syncLine);
      } else {
        return const SizedBox.shrink();
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    final lyricFontSize = lyricViewController.lyricFontSize;
    final translationFontSize = lyricViewController.translationFontSize;
    final alignment = lyricViewController.lyricTextAlign;
    final presentation = presentLyricLine(
      syncLine,
      showTranslation: lyricViewController.showTranslation,
    );

    if (!isMainLine) {
      if (syncLine.words.isEmpty) {
        return const SizedBox.shrink();
      }

      final List<Text> contents = [
        buildPrimaryText(
          presentation.primary,
          scheme,
          alignment,
          lyricFontSize,
        ),
      ];
      if (presentation.translation != null) {
        contents.add(buildSecondaryText(
          presentation.translation!,
          scheme,
          alignment,
          translationFontSize,
        ));
      }

      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: switch (alignment) {
            LyricTextAlign.left => CrossAxisAlignment.start,
            LyricTextAlign.center => CrossAxisAlignment.center,
            LyricTextAlign.right => CrossAxisAlignment.end,
          },
          children: contents,
        ),
      );
    }

    final List<Widget> contents = [
      StreamBuilder(
        stream: PlayService.instance.playbackService.positionStream,
        builder: (context, snapshot) {
          final audioPosition = Duration(
            microseconds:
                ((snapshot.data ?? 0) * Duration.microsecondsPerSecond).round(),
          );
          return RichText(
            textAlign: switch (alignment) {
              LyricTextAlign.left => TextAlign.left,
              LyricTextAlign.center => TextAlign.center,
              LyricTextAlign.right => TextAlign.right,
            },
            text: TextSpan(
              children: List.generate(
                syncLine.words.length,
                (i) {
                  final progress = lyricWordProgress(
                    audioPosition: audioPosition,
                    wordStart: syncLine.words[i].start,
                    wordLength: syncLine.words[i].length,
                    offset: PlayService.instance.lyricService.lyricOffset,
                  );
                  return WidgetSpan(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: [
                            scheme.primary,
                            scheme.primary,
                            scheme.primary.withOpacity(0.10),
                            scheme.primary.withOpacity(0.10),
                          ],
                          stops: [0, progress, progress, 1],
                        ).createShader(bounds);
                      },
                      child: Text(
                        syncLine.words[i].content,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: lyricFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      )
    ];
    if (presentation.translation != null) {
      contents.add(buildSecondaryText(
        presentation.translation!,
        scheme,
        alignment,
        translationFontSize,
      ));
    }
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: switch (alignment) {
          LyricTextAlign.left => CrossAxisAlignment.start,
          LyricTextAlign.center => CrossAxisAlignment.center,
          LyricTextAlign.right => CrossAxisAlignment.end,
        },
        children: contents,
      ),
    );
  }

  Text buildPrimaryText(
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(
        color: scheme.onSecondaryContainer,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Text buildSecondaryText(
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: fontSize),
    );
  }
}

class _LrcLineContent extends StatelessWidget {
  const _LrcLineContent({required this.lrcLine, required this.isMainLine});

  final LrcLine lrcLine;
  final bool isMainLine;

  @override
  Widget build(BuildContext context) {
    if (lrcLine.isBlank) {
      if (lrcLine.length > const Duration(seconds: 5) && isMainLine) {
        return LyricTransitionTile(lrcLine: lrcLine);
      } else {
        return const SizedBox.shrink();
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    final lyricFontSize = lyricViewController.lyricFontSize;
    final translationFontSize = lyricViewController.translationFontSize;
    final alignment = lyricViewController.lyricTextAlign;
    final presentation = presentLyricLine(
      lrcLine,
      showTranslation: lyricViewController.showTranslation,
    );
    final List<Text> contents = [
      buildPrimaryText(
        presentation.primary,
        scheme,
        alignment,
        lyricFontSize,
      ),
    ];
    if (presentation.translation != null) {
      contents.add(buildSecondaryText(
        presentation.translation!,
        scheme,
        alignment,
        translationFontSize,
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: switch (alignment) {
          LyricTextAlign.left => CrossAxisAlignment.start,
          LyricTextAlign.center => CrossAxisAlignment.center,
          LyricTextAlign.right => CrossAxisAlignment.end,
        },
        children: contents,
      ),
    );
  }

  Text buildPrimaryText(
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(
        color: scheme.onSecondaryContainer,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Text buildSecondaryText(
    String text,
    ColorScheme scheme,
    LyricTextAlign align,
    double fontSize,
  ) {
    return Text(
      text,
      textAlign: switch (align) {
        LyricTextAlign.left => TextAlign.left,
        LyricTextAlign.center => TextAlign.center,
        LyricTextAlign.right => TextAlign.right,
      },
      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: fontSize),
    );
  }
}

/// 歌词间奏表示
/// lrcLine 和 syncLine 必须有且只有一个不为空
class LyricTransitionTile extends StatefulWidget {
  final LrcLine? lrcLine;
  final SyncLyricLine? syncLine;
  final Stream<double>? positionStream;
  final Duration Function()? lyricOffset;
  const LyricTransitionTile(
      {super.key,
      this.lrcLine,
      this.syncLine,
      this.positionStream,
      this.lyricOffset})
      : assert((lrcLine == null) != (syncLine == null));

  @override
  State<LyricTransitionTile> createState() => _LyricTransitionTileState();
}

class _LyricTransitionTileState extends State<LyricTransitionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  StreamSubscription<double>? _positionSubscription;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
    _listen();
  }

  void _listen() {
    _positionSubscription = (widget.positionStream ??
            PlayService.instance.playbackService.positionStream)
        .listen((position) {
      final line = widget.lrcLine ?? widget.syncLine!;
      final length = widget.lrcLine?.length ?? widget.syncLine!.length;
      final progress = lyricWordProgress(
        audioPosition: Duration(
            microseconds: (position * Duration.microsecondsPerSecond).round()),
        wordStart: line.start,
        wordLength: length,
        offset: widget.lyricOffset?.call() ??
            PlayService.instance.lyricService.lyricOffset,
      );
      if (progress >= 1) {
        _animation.stop();
      } else if (!_animation.isAnimating) {
        _animation.repeat(reverse: true);
      }
      setState(() => _progress = progress);
    });
  }

  @override
  void didUpdateWidget(covariant LyricTransitionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _positionSubscription?.cancel();
      _listen();
    }
    if (oldWidget.lrcLine != widget.lrcLine ||
        oldWidget.syncLine != widget.syncLine) {
      _progress = 0;
      if (!_animation.isAnimating) _animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40.0,
      width: 80.0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) => CustomPaint(
            painter:
                LyricTransitionPainter(scheme, _progress, _animation.value),
          ),
        ),
      ),
    );
  }
}

class LyricTransitionPainter extends CustomPainter {
  final ColorScheme scheme;
  final double progress;
  final double sizeFactor;

  final Paint circlePaint1 = Paint();
  final Paint circlePaint2 = Paint();
  final Paint circlePaint3 = Paint();

  final double radius = 6;

  LyricTransitionPainter(this.scheme, this.progress, this.sizeFactor);

  @override
  void paint(Canvas canvas, Size size) {
    circlePaint1.color = scheme.onSecondaryContainer.withOpacity(
      0.05 + min(progress * 3, 1) * 0.95,
    );
    circlePaint2.color = scheme.onSecondaryContainer.withOpacity(
      0.05 + min(max(progress - 1 / 3, 0) * 3, 1) * 0.95,
    );
    circlePaint3.color = scheme.onSecondaryContainer.withOpacity(
      0.05 + min(max(progress - 2 / 3, 0) * 3, 1) * 0.95,
    );

    final rWithFactor = radius + sizeFactor;
    final c1 = Offset(rWithFactor, 8);
    final c2 = Offset(4 * rWithFactor, 8);
    final c3 = Offset(7 * rWithFactor, 8);

    canvas.drawCircle(c1, rWithFactor, circlePaint1);
    canvas.drawCircle(c2, rWithFactor, circlePaint2);
    canvas.drawCircle(c3, rWithFactor, circlePaint3);
  }

  @override
  bool shouldRepaint(LyricTransitionPainter oldDelegate) =>
      oldDelegate.scheme != scheme ||
      oldDelegate.progress != progress ||
      oldDelegate.sizeFactor != sizeFactor;

  @override
  bool shouldRebuildSemantics(LyricTransitionPainter oldDelegate) => false;
}
