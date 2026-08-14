import 'package:coriander_player/component/artwork_thumbnail.dart';
import 'package:flutter/material.dart';

const double _barAreaHeight = 168;
const double _artworkSize = 40;
const double _columnWidth = 88;

class ListeningDurationChartItem {
  const ListeningDurationChartItem({
    required this.label,
    required this.listened,
    required this.playCount,
    required this.artwork,
    required this.onTap,
  });

  final String label;
  final Duration listened;
  final int playCount;
  final Future<ImageProvider?>? artwork;
  final VoidCallback? onTap;
}

class ListeningDurationChart extends StatelessWidget {
  const ListeningDurationChart({
    super.key,
    required this.items,
    this.keyPrefix = '',
  });

  final List<ListeningDurationChartItem> items;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('暂无数据');

    final maxListened = items.fold<int>(
      0,
      (maximum, item) => item.listened.inMilliseconds > maximum
          ? item.listened.inMilliseconds
          : maximum,
    );
    return SizedBox(
      height: 276,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DurationAxis(maxListened: Duration(milliseconds: maxListened)),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('listening-chart-scroll'),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in items)
                    _DurationColumn(
                      item: item,
                      heightFactor: maxListened == 0
                          ? 0
                          : item.listened.inMilliseconds / maxListened,
                      keyPrefix: keyPrefix,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationAxis extends StatelessWidget {
  const _DurationAxis({required this.maxListened});

  final Duration maxListened;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Padding(
        padding: const EdgeInsets.only(top: _artworkSize + 4),
        child: SizedBox(
          height: _barAreaHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < 4; index++)
                Positioned(
                  left: 0,
                  right: 4,
                  top: index * (_barAreaHeight / 3) - (index == 3 ? 14 : 0),
                  child: Text(
                    formatListeningDuration(
                      Duration(
                        milliseconds:
                            maxListened.inMilliseconds * (3 - index) ~/ 3,
                      ),
                    ),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationColumn extends StatelessWidget {
  const _DurationColumn({
    required this.item,
    required this.heightFactor,
    required this.keyPrefix,
  });

  final ListeningDurationChartItem item;
  final double heightFactor;
  final String keyPrefix;

  String get _keyLabel =>
      keyPrefix.isEmpty ? item.label : '$keyPrefix-${item.label}';

  @override
  Widget build(BuildContext context) {
    final barHeight = _barAreaHeight * heightFactor.clamp(0.0, 1.0);
    return SizedBox(
      width: _columnWidth,
      child: InkWell(
        key: ValueKey('listening-chart-item-$_keyLabel'),
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          button: item.onTap != null,
          label:
              '${item.label}，${formatListeningDuration(item.listened)}，${item.playCount} 次',
          child: Column(
            children: [
              SizedBox(
                height: _artworkSize + 4 + _barAreaHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArtworkThumbnail(image: item.artwork, size: _artworkSize),
                      const SizedBox(height: 4),
                      SizedBox(
                        key: ValueKey('listening-chart-bar-$_keyLabel'),
                        width: 32,
                        height: barHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Tooltip(
                message: item.label,
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              Text('${item.playCount} 次'),
            ],
          ),
        ),
      ),
    );
  }
}

String formatListeningDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours小时$minutes分';
  if (minutes > 0) return '$minutes分$seconds秒';
  return '$seconds秒';
}
