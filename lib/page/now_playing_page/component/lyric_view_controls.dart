import 'dart:async';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/lyric/lyric_presentation.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:coriander_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

enum LyricTextAlign {
  left,
  center,
  right;

  static LyricTextAlign? fromString(String lyricTextAlign) {
    for (var value in LyricTextAlign.values) {
      if (value.name == lyricTextAlign) return value;
    }
    return null;
  }
}

class LyricViewController extends ChangeNotifier {
  LyricViewController({
    NowPlayingPagePreference? preference,
    Future<void> Function()? savePreference,
  })  : nowPlayingPagePref =
            preference ?? AppPreference.instance.nowPlayingPagePref,
        _savePreference = savePreference ?? AppPreference.instance.save;

  final NowPlayingPagePreference nowPlayingPagePref;
  final Future<void> Function() _savePreference;
  late LyricTextAlign lyricTextAlign = nowPlayingPagePref.lyricTextAlign;
  late double lyricFontSize = nowPlayingPagePref.lyricFontSize;
  late double translationFontSize = nowPlayingPagePref.translationFontSize;
  int get lyricOffsetMs => nowPlayingPagePref.lyricOffsetMs;
  bool get showTranslation => nowPlayingPagePref.showTranslation;

  void increaseLyricOffset() {
    _setLyricOffsetMs(lyricOffsetMs + lyricOffsetStepMs);
  }

  void decreaseLyricOffset() {
    _setLyricOffsetMs(lyricOffsetMs - lyricOffsetStepMs);
  }

  void resetLyricOffset() {
    _setLyricOffsetMs(0);
  }

  void toggleTranslation() {
    nowPlayingPagePref.setShowTranslation(!showTranslation);
    unawaited(_savePreference());
    notifyListeners();
  }

  void _setLyricOffsetMs(int value) {
    final previousValue = lyricOffsetMs;
    nowPlayingPagePref.setLyricOffsetMs(value);
    if (lyricOffsetMs == previousValue) return;

    unawaited(_savePreference());
    notifyListeners();
  }

  /// 在左对齐、居中、右对齐之间循环切换
  void switchLyricTextAlign() {
    lyricTextAlign = switch (lyricTextAlign) {
      LyricTextAlign.left => LyricTextAlign.center,
      LyricTextAlign.center => LyricTextAlign.right,
      LyricTextAlign.right => LyricTextAlign.left,
    };

    nowPlayingPagePref.lyricTextAlign = lyricTextAlign;
    notifyListeners();
  }

  void increaseFontSize() {
    lyricFontSize += 1;
    translationFontSize += 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }

  void decreaseFontSize() {
    if (translationFontSize <= 14) return;

    lyricFontSize -= 1;
    translationFontSize -= 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }
}

class LyricViewControls extends StatelessWidget {
  const LyricViewControls({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SetLyricSourceBtn(),
          SizedBox(height: 8.0),
          _LyricOffsetBtn(),
          SizedBox(height: 8.0),
          _TranslationVisibilityBtn(),
          SizedBox(height: 8.0),
          _LyricAlignSwitchBtn(),
          SizedBox(height: 8.0),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IncreaseFontSizeBtn(),
              SizedBox(width: 8.0),
              _DecreaseFontSizeBtn(),
            ],
          )
        ],
      ),
    );
  }
}

class _LyricOffsetBtn extends StatelessWidget {
  const _LyricOffsetBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();
    final offset = lyricViewController.lyricOffsetMs;
    final offsetLabel = _formatLyricOffset(offset);

    return MenuAnchor(
      onOpen: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = true;
      },
      onClose: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
      },
      menuChildren: [
        MenuItemButton(
          onPressed: offset <= -lyricOffsetLimitMs
              ? null
              : lyricViewController.decreaseLyricOffset,
          leadingIcon: const Icon(Symbols.remove),
          child: const Text('减小 100 毫秒'),
        ),
        MenuItemButton(
          onPressed: null,
          leadingIcon: const Icon(Symbols.timer),
          child: Text('当前：$offsetLabel'),
        ),
        MenuItemButton(
          onPressed: offset >= lyricOffsetLimitMs
              ? null
              : lyricViewController.increaseLyricOffset,
          leadingIcon: const Icon(Symbols.add),
          child: const Text('增大 100 毫秒'),
        ),
        MenuItemButton(
          onPressed: offset == 0 ? null : lyricViewController.resetLyricOffset,
          leadingIcon: const Icon(Symbols.restart_alt),
          child: const Text('重置为 0 毫秒'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        tooltip: '调整歌词偏移；当前：$offsetLabel',
        color: scheme.onSecondaryContainer,
        icon: const Icon(Symbols.timer),
      ),
    );
  }
}

class _TranslationVisibilityBtn extends StatelessWidget {
  const _TranslationVisibilityBtn();

  @override
  Widget build(BuildContext context) {
    final lyricService = PlayService.instance.lyricService;
    return ListenableBuilder(
      listenable: lyricService,
      builder: (context, _) => FutureBuilder(
        future: lyricService.currLyricFuture,
        builder: (context, snapshot) {
          final lyric = snapshot.data;
          if (lyric == null || !lyricHasTranslation(lyric)) {
            return const SizedBox.shrink();
          }

          final scheme = Theme.of(context).colorScheme;
          final lyricViewController = context.watch<LyricViewController>();
          return IconButton(
            onPressed: lyricViewController.toggleTranslation,
            tooltip: lyricViewController.showTranslation ? '隐藏歌词翻译' : '显示歌词翻译',
            color: scheme.onSecondaryContainer,
            icon: Icon(
              Symbols.translate,
              fill: lyricViewController.showTranslation ? 1 : 0,
            ),
          );
        },
      ),
    );
  }
}

String _formatLyricOffset(int offsetMs) {
  final sign = offsetMs > 0 ? '+' : '';
  return '$sign$offsetMs 毫秒';
}

class _LyricAlignSwitchBtn extends StatelessWidget {
  const _LyricAlignSwitchBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.switchLyricTextAlign,
      tooltip: "切换歌词对齐方向",
      color: scheme.onSecondaryContainer,
      icon: Icon(switch (lyricViewController.lyricTextAlign) {
        LyricTextAlign.left => Symbols.format_align_left,
        LyricTextAlign.center => Symbols.format_align_center,
        LyricTextAlign.right => Symbols.format_align_right,
      }),
    );
  }
}

class _IncreaseFontSizeBtn extends StatelessWidget {
  const _IncreaseFontSizeBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.increaseFontSize,
      tooltip: "增大歌词字体",
      color: scheme.onSecondaryContainer,
      icon: const Icon(Symbols.text_increase),
    );
  }
}

class _DecreaseFontSizeBtn extends StatelessWidget {
  const _DecreaseFontSizeBtn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.decreaseFontSize,
      tooltip: "减小歌词字体",
      color: scheme.onSecondaryContainer,
      icon: const Icon(Symbols.text_decrease),
    );
  }
}
