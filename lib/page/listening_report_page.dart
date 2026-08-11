import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/listening_report.dart';
import 'package:coriander_player/library/playback_history_models.dart';
import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/play_service/play_service.dart';
import 'package:coriander_player/play_service/playback_history_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ListeningReportPage extends StatefulWidget {
  const ListeningReportPage({
    super.key,
    this.historyService,
    this.audios,
    this.now,
  });

  final PlaybackHistoryService? historyService;
  final Iterable<Audio>? audios;
  final DateTime Function()? now;

  @override
  State<ListeningReportPage> createState() => _ListeningReportPageState();
}

class _ListeningReportPageState extends State<ListeningReportPage> {
  _ReportRange _range = _ReportRange.week;

  PlaybackHistoryService? get _historyService =>
      widget.historyService ?? PlayService.instance.playbackHistoryService;

  DateTime get _now => (widget.now ?? DateTime.now)();

  Iterable<Audio> get _audios =>
      widget.audios ?? AudioLibrary.instance.audioCollection;

  @override
  Widget build(BuildContext context) {
    final historyService = _historyService;
    if (historyService == null) {
      return const PageScaffold(
        title: '听歌报告',
        actions: [],
        body: Center(child: Text('听歌报告暂不可用')),
      );
    }

    return AnimatedBuilder(
      animation: historyService,
      builder: (context, _) => _ReportContent(
        range: _range,
        onRangeChanged: (range) => setState(() => _range = range),
        period: _periodFor(_range, _now),
        events: historyService.events,
        audios: _audios,
      ),
    );
  }
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({
    required this.range,
    required this.onRangeChanged,
    required this.period,
    required this.events,
    required this.audios,
  });

  final _ReportRange range;
  final ValueChanged<_ReportRange> onRangeChanged;
  final ReportPeriod period;
  final Iterable<PlaybackHistoryEvent> events;
  final Iterable<Audio> audios;

  @override
  Widget build(BuildContext context) {
    final metadata = _ReportMetadata.fromAudios(audios);
    final report = buildListeningReport(events, period, metadata.audiosByPath);
    if (report.qualifiedPlayCount == 0) {
      return PageScaffold(
        title: '听歌报告',
        actions: const [],
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PeriodChooser(selected: range, onChanged: onRangeChanged),
            const SizedBox(height: 24),
            const Center(child: Text('这个周期还没有有效播放记录')),
          ],
        ),
      );
    }

    return PageScaffold(
      title: '听歌报告',
      actions: const [],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PeriodChooser(selected: range, onChanged: onRangeChanged),
          const SizedBox(height: 16),
          _SummaryCards(report: report),
          const SizedBox(height: 16),
          _RankSection(
            title: '歌曲 Top 10',
            ranks: report.songRanks,
            total: report.totalListened,
            destinationFor: (rank) {
              final audio = metadata.audiosByPath[rank.key];
              return audio == null
                  ? null
                  : _ReportDestination(app_paths.AUDIO_DETAIL_PAGE, audio);
            },
          ),
          const SizedBox(height: 16),
          _RankSection(
            title: '歌手 Top 10',
            ranks: report.artistRanks,
            total: report.totalListened,
            destinationFor: (rank) {
              final artist = metadata.artistsByName[rank.key];
              return artist == null
                  ? null
                  : _ReportDestination(app_paths.ARTIST_DETAIL_PAGE, artist);
            },
          ),
          const SizedBox(height: 16),
          _RankSection(
            title: '专辑 Top 10',
            ranks: report.albumRanks,
            total: report.totalListened,
            destinationFor: (rank) {
              final album = metadata.albumsByName[rank.key];
              return album == null
                  ? null
                  : _ReportDestination(app_paths.ALBUM_DETAIL_PAGE, album);
            },
          ),
        ],
      ),
    );
  }
}

class _PeriodChooser extends StatelessWidget {
  const _PeriodChooser({required this.selected, required this.onChanged});

  final _ReportRange selected;
  final ValueChanged<_ReportRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _ReportRange.values
          .map(
            (range) => ChoiceChip(
              label: Text(range.label),
              selected: selected == range,
              onSelected: (_) => onChanged(range),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.report});

  final ListeningReport report;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCard(
        key: const ValueKey('total-duration'),
        label: '总听歌时长',
        value: _formatDuration(report.totalListened),
      ),
      _SummaryCard(
        key: const ValueKey('qualified'),
        label: '有效播放',
        value: '${report.qualifiedPlayCount} 次',
      ),
      _SummaryCard(
        key: const ValueKey('song-count'),
        label: '歌曲',
        value: '${report.songCount} 首',
      ),
      _SummaryCard(
        key: const ValueKey('artist-count'),
        label: '歌手',
        value: '${report.artistCount} 位',
      ),
      _SummaryCard(
        key: const ValueKey('album-count'),
        label: '专辑',
        value: '${report.albumCount} 张',
      ),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: SizedBox(
          width: 160,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      );
}

class _RankSection extends StatelessWidget {
  const _RankSection({
    required this.title,
    required this.ranks,
    required this.total,
    required this.destinationFor,
  });

  final String title;
  final List<ListeningRank> ranks;
  final Duration total;
  final _ReportDestination? Function(ListeningRank rank) destinationFor;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (ranks.isEmpty)
                const Text('暂无数据')
              else
                ...ranks.indexed.map((entry) {
                  final rank = entry.$2;
                  final destination = destinationFor(rank);
                  final ratio = total.inMilliseconds == 0
                      ? 0.0
                      : rank.listened.inMilliseconds / total.inMilliseconds;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${entry.$1 + 1}'),
                    title: Text(rank.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${rank.playCount} 次 · ${_formatDuration(rank.listened)}'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: ratio.clamp(0.0, 1.0).toDouble(),
                        ),
                      ],
                    ),
                    onTap: destination == null
                        ? null
                        : () => context.push(destination.path,
                            extra: destination.extra),
                  );
                }),
            ],
          ),
        ),
      );
}

class _ReportDestination {
  const _ReportDestination(this.path, this.extra);

  final String path;
  final Object extra;
}

class _ReportMetadata {
  _ReportMetadata._(
    this.audiosByPath,
    this.artistsByName,
    this.albumsByName,
  );

  final Map<String, Audio> audiosByPath;
  final Map<String, Artist> artistsByName;
  final Map<String, Album> albumsByName;

  factory _ReportMetadata.fromAudios(Iterable<Audio> audios) {
    final audiosByPath = <String, Audio>{};
    final artistsByName = <String, Artist>{};
    final albumsByName = <String, Album>{};

    for (final audio in audios) {
      audiosByPath[audio.path] = audio;
      final artist = audio.artist.trim().isEmpty
          ? null
          : artistsByName.putIfAbsent(
              audio.artist,
              () => Artist(name: audio.artist),
            );
      final album = audio.album.trim().isEmpty
          ? null
          : albumsByName.putIfAbsent(
              audio.album,
              () => Album(name: audio.album),
            );
      artist?.works.add(audio);
      album?.works.add(audio);
      if (artist != null && album != null) {
        artist.albumsMap[album.name] = album;
        album.artistsMap[artist.name] = artist;
      }
    }

    return _ReportMetadata._(audiosByPath, artistsByName, albumsByName);
  }
}

enum _ReportRange {
  week('本周'),
  month('本月'),
  year('近12个月');

  const _ReportRange(this.label);

  final String label;
}

ReportPeriod _periodFor(_ReportRange range, DateTime now) => switch (range) {
      _ReportRange.week => ReportPeriod.currentWeek(now),
      _ReportRange.month => ReportPeriod.currentMonth(now),
      _ReportRange.year => ReportPeriod.recentTwelveMonths(now),
    };

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours小时$minutes分';
  if (minutes > 0) return '$minutes分$seconds秒';
  return '$seconds秒';
}
