import 'dart:async';
import 'dart:math';

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/lyric/lrc.dart';
import 'package:coriander_player/lyric/lyric.dart';
import 'package:coriander_player/lyric/lyric_presentation.dart';
import 'package:coriander_player/lyric/lyric_source.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/music_matcher.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

LyricLine lyricSourcePreviewLine(
  Lyric lyric,
  Duration audioPosition,
  Duration offset,
) {
  final lyricPosition = lyricClockPosition(audioPosition, offset);
  final index = max(
    lyric.lines.lastIndexWhere((line) => line.start <= lyricPosition),
    0,
  );
  return lyric.lines[index];
}

String lyricSourcePreviewText(
  LyricLine line, {
  required bool showTranslation,
}) {
  final presentation = presentLyricLine(
    line,
    showTranslation: showTranslation,
  );
  final translation = presentation.translation;
  return '当前：${presentation.primary}'
      '${translation == null ? '' : '┃$translation'}';
}

String lyricSourceName(ResultSource source) => switch (source) {
      ResultSource.qq => 'QQ音乐',
      ResultSource.kugou => '酷狗音乐',
      ResultSource.netease => '网易云音乐',
    };

String lyricProviderStatusText(LyricProviderSearchStatus status) {
  final source = lyricSourceName(status.source);
  final count = status.candidateCount;
  final detail = status.errorMessage?.trim();
  return switch (status.state) {
    LyricProviderSearchState.searching => '$source：搜索中…',
    LyricProviderSearchState.found => '$source：找到 $count 条候选',
    LyricProviderSearchState.noResults => '$source：无有效结果',
    LyricProviderSearchState.failed =>
      '$source：搜索失败${detail == null || detail.isEmpty ? '' : '（$detail）'}',
    LyricProviderSearchState.partial =>
      '$source：找到 $count 条（${detail == null || detail.isEmpty ? '部分失败' : detail}）',
  };
}

String lyricSourceMatchSummary(SongSearchResult result) {
  final source = lyricSourceName(result.source);
  final reasons =
      result.matchReasons.isEmpty ? '无' : result.matchReasons.join('、');
  final cached = result.fromCache ? ' · 已缓存' : '';
  return '来源：$source · 匹配度：${(result.score * 100).round()}% · 依据：$reasons$cached';
}

Future<String?> showLyricSourceDialog({
  required NavigatorState navigator,
  required Audio audio,
  OnlineLyricSearchController? searchController,
}) {
  return showDialog<String>(
    context: navigator.context,
    builder: (context) => _SetLyricSourceDialog(
      audio: audio,
      searchController: searchController,
    ),
  );
}

class SetLyricSourceBtn extends StatelessWidget {
  const SetLyricSourceBtn({
    required this.onMenuOpen,
    required this.onMenuClose,
    super.key,
  });

  final VoidCallback onMenuOpen;
  final VoidCallback onMenuClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayService.instance.lyricService,
      builder: (context, _) => FutureBuilder(
        future: PlayService.instance.lyricService.currLyricFuture,
        builder: (context, snapshot) {
          const loadingWidget = IconButton(
            onPressed: null,
            tooltip: '歌词来源',
            icon: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(),
            ),
          );
          final lyricNullable = snapshot.data;
          final isLocal = lyricNullable == null
              ? null
              : (lyricNullable is Lrc &&
                  lyricNullable.source == LrcSource.local);
          return switch (snapshot.connectionState) {
            ConnectionState.none => loadingWidget,
            ConnectionState.waiting => loadingWidget,
            ConnectionState.active => loadingWidget,
            ConnectionState.done => _SetLyricSourceBtn(
                isLocal: isLocal,
                onMenuOpen: onMenuOpen,
                onMenuClose: onMenuClose,
              ),
          };
        },
      ),
    );
  }
}

class _SetLyricSourceBtn extends StatelessWidget {
  final bool? isLocal;
  final VoidCallback onMenuOpen;
  final VoidCallback onMenuClose;

  const _SetLyricSourceBtn({
    required this.onMenuOpen,
    required this.onMenuClose,
    this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricService = PlayService.instance.lyricService;
    final navigator = Navigator.of(context, rootNavigator: true);
    return MenuAnchor(
      onOpen: onMenuOpen,
      onClose: onMenuClose,
      menuChildren: [
        MenuItemButton(
          onPressed: () {
            final nowPlaying = PlayService.instance.playbackService.nowPlaying;
            if (nowPlaying == null || !navigator.mounted) return;
            unawaited(showLyricSourceDialog(
              navigator: navigator,
              audio: nowPlaying,
            ));
          },
          child: const Text("选择歌词源"),
        ),
        MenuItemButton(
          onPressed: lyricService.useOnlineLyric,
          leadingIcon: isLocal == false ? const Icon(Symbols.check) : null,
          child: const Text("在线"),
        ),
        MenuItemButton(
          onPressed: lyricService.useLocalLyric,
          leadingIcon: isLocal == true ? const Icon(Symbols.check) : null,
          child: const Text("本地"),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: PlayService.instance.playbackService.nowPlaying == null
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
        icon: const Icon(Symbols.lyrics),
        tooltip: '选择歌词来源',
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

class _SetLyricSourceDialog extends StatefulWidget {
  const _SetLyricSourceDialog({required this.audio, this.searchController});

  final Audio audio;
  final OnlineLyricSearchController? searchController;

  @override
  State<_SetLyricSourceDialog> createState() => _SetLyricSourceDialogState();
}

class _SetLyricSourceDialogState extends State<_SetLyricSourceDialog> {
  Audio get audio => widget.audio;
  late final OnlineLyricSearchController _search;
  late final TextEditingController _title;
  late final TextEditingController _artist;
  String? _queryError;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: audio.title);
    _artist = TextEditingController(text: audio.artist);
    _search =
        widget.searchController ?? OnlineLyricSearchController(audio: audio);
    unawaited(_search.start());
  }

  void _searchAgain() {
    if (_title.text.trim().isEmpty) {
      setState(() => _queryError = '请填写歌曲标题');
      return;
    }
    setState(() => _queryError = null);
    FocusScope.of(context).unfocus();
    unawaited(_search.start(title: _title.text, artist: _artist.text));
  }

  @override
  void dispose() {
    _search.cancel();
    if (widget.searchController == null) _search.dispose();
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 640,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  "选择歌词源",
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: Row(children: [
                  Expanded(
                      child: TextField(
                    key: const Key('lyric-search-title'),
                    controller: _title,
                    decoration: InputDecoration(
                        labelText: '歌曲标题', errorText: _queryError),
                    onSubmitted: (_) => _searchAgain(),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                    key: const Key('lyric-search-artist'),
                    controller: _artist,
                    decoration: const InputDecoration(labelText: '歌手（可选）'),
                    onSubmitted: (_) => _searchAgain(),
                  )),
                  IconButton(
                      onPressed: _searchAgain,
                      tooltip: '重新搜索歌词',
                      icon: const Icon(Symbols.search)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('仅调整本次搜索条件，不修改歌曲标签'),
              ),
              ListTile(
                title: const Text("使用本地歌词"),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                onTap: () {
                  setLyricSourceForPath(
                    audio.path,
                    LyricSource(LyricSourceType.local),
                  );
                  PlayService.instance.lyricService
                      .useLocalLyric(forAudio: audio);
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              Expanded(
                child: ListenableBuilder(
                  listenable: _search,
                  builder: (context, _) {
                    final report = _search.report;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LyricProviderStatusStrip(
                            statuses: report.statuses,
                            onRetry: (source) =>
                                unawaited(_search.retry(source))),
                        if (_search.isSearching)
                          const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        Expanded(
                          child: report.candidates.isEmpty
                              ? (_search.isSearching
                                  ? const Center(child: Text('正在搜索歌词，结果将陆续显示…'))
                                  : const _LyricSearchEmptyState())
                              : ListView.builder(
                                  itemCount: report.candidates.length,
                                  itemBuilder: (context, i) => _LyricSourceTile(
                                    key: ValueKey(_search
                                        .candidateKey(report.candidates[i])),
                                    audio: audio,
                                    searchResult: report.candidates[i],
                                    search: _search,
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricProviderStatusStrip extends StatelessWidget {
  const _LyricProviderStatusStrip(
      {required this.statuses, required this.onRetry});

  final List<LyricProviderSearchStatus> statuses;
  final ValueChanged<ResultSource> onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) => Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final status in statuses)
                  Tooltip(
                    message:
                        status.errorMessage ?? lyricProviderStatusText(status),
                    child: InputChip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        switch (status.state) {
                          LyricProviderSearchState.searching =>
                            Symbols.hourglass_top,
                          LyricProviderSearchState.found =>
                            Symbols.check_circle,
                          LyricProviderSearchState.noResults =>
                            Symbols.search_off,
                          LyricProviderSearchState.failed => Symbols.error,
                          LyricProviderSearchState.partial => Symbols.warning,
                        },
                        size: 16,
                      ),
                      onDeleted:
                          status.state == LyricProviderSearchState.searching
                              ? null
                              : () => onRetry(status.source),
                      deleteIcon: const Icon(Symbols.refresh, size: 16),
                      deleteButtonTooltipMessage:
                          '重试${lyricSourceName(status.source)}',
                      label: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth:
                                (constraints.maxWidth - 100).clamp(0.0, 260.0)),
                        child: Text(
                          lyricProviderStatusText(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ));
  }
}

class _LyricSearchEmptyState extends StatelessWidget {
  const _LyricSearchEmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Text(
          '没有找到可用歌词候选\n请检查歌曲标题、歌手标签或网络连接',
          textAlign: TextAlign.center,
        ),
      );
}

class _LyricSourceTile extends StatefulWidget {
  const _LyricSourceTile({
    super.key,
    required this.searchResult,
    required this.audio,
    required this.search,
  });

  final Audio audio;
  final SongSearchResult searchResult;
  final OnlineLyricSearchController search;

  @override
  State<_LyricSourceTile> createState() => _LyricSourceTileState();
}

class _LyricSourceTileState extends State<_LyricSourceTile> {
  late final lyric = getOnlineLyric(
    audio: widget.audio,
    candidate: widget.searchResult,
    providers: widget.search.providers,
    cache: widget.search.cache,
  );
  @override
  Widget build(BuildContext context) {
    final loadingWidget = ListTile(
      title: Text(widget.searchResult.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(lyricSourceMatchSummary(widget.searchResult),
          maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(),
      ),
    );
    return FutureBuilder(
      future: lyric,
      builder: (context, lyricSnapshot) =>
          switch (lyricSnapshot.connectionState) {
        ConnectionState.none => loadingWidget,
        ConnectionState.waiting => loadingWidget,
        ConnectionState.active => loadingWidget,
        ConnectionState.done =>
          lyricSnapshot.data == null || lyricSnapshot.data!.lines.isEmpty
              ? buildFailedTile(widget.searchResult)
              : buildTile(
                  context,
                  widget.audio,
                  widget.searchResult,
                  lyricSnapshot.data!,
                ),
      },
    );
  }

  Widget buildFailedTile(SongSearchResult searchResult) => ListTile(
        enabled: false,
        leading: const Icon(Symbols.error),
        title: Text(
          searchResult.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${lyricSourceMatchSummary(searchResult)}\n歌词加载失败',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget buildTile(
    BuildContext context,
    Audio audio,
    SongSearchResult searchResult,
    Lyric lyric,
  ) {
    return ListTile(
      onTap: () {
        LyricSourceType source = switch (searchResult.source) {
          ResultSource.qq => LyricSourceType.qq,
          ResultSource.kugou => LyricSourceType.kugou,
          ResultSource.netease => LyricSourceType.netease,
        };
        setLyricSourceForPath(
            audio.path,
            LyricSource(
              source,
              qqSongId: searchResult.qqSongId,
              kugouSongHash: searchResult.kugouSongHash,
              neteaseSongId: searchResult.neteaseSongId,
            ));
        PlayService.instance.lyricService
            .useSpecificLyric(lyric, forAudio: audio);

        Navigator.pop(context);
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      leading: Text(lyric is Lrc ? "LRC" : "逐字"),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            searchResult.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            "${searchResult.artists} - ${searchResult.album}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            lyricSourceMatchSummary(searchResult),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      subtitle: StreamBuilder(
        stream: PlayService.instance.playbackService.positionStream,
        builder: (context, positionSnapshot) {
          final playbackPosition = Duration(
            microseconds:
                ((positionSnapshot.data ?? 0) * Duration.microsecondsPerSecond)
                    .round(),
          );
          final currLine = lyricSourcePreviewLine(
            lyric,
            playbackPosition,
            PlayService.instance.lyricService.lyricOffset,
          );
          return Text(
            lyricSourcePreviewText(
              currLine,
              showTranslation:
                  AppPreference.instance.nowPlayingPagePref.showTranslation,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
    );
  }
}
