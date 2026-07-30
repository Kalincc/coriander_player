import 'package:coriander_player/library/lyric_search_models.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

String formatLyricTimestamp(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class LyricSearchResultTile extends StatelessWidget {
  final LyricSearchMatch match;
  final String query;
  final VoidCallback onLocate;

  const LyricSearchResultTile({
    super.key,
    required this.match,
    required this.query,
    required this.onLocate,
  });

  List<InlineSpan> _highlightedSpans(ColorScheme scheme, String text) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return [TextSpan(text: text)];

    final matches = RegExp(
      RegExp.escape(normalizedQuery),
      caseSensitive: false,
    ).allMatches(text);
    final spans = <InlineSpan>[];
    var previousEnd = 0;
    for (final match in matches) {
      if (match.start > previousEnd) {
        spans.add(TextSpan(text: text.substring(previousEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            backgroundColor: scheme.primaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      previousEnd = match.end;
    }
    if (previousEnd < text.length) {
      spans.add(TextSpan(text: text.substring(previousEnd)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audio = match.audio;
    final placeholder = Icon(
      Symbols.broken_image,
      size: 48,
      color: scheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onLocate,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          FutureBuilder<ImageProvider?>(
                            future: audio.cover,
                            builder: (context, snapshot) {
                              final cover = snapshot.data;
                              if (cover == null) return placeholder;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image(
                                  image: cover,
                                  width: 48,
                                  height: 48,
                                  errorBuilder: (_, __, ___) => placeholder,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  audio.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${audio.artist} - ${audio.album}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '在音乐库中定位',
                  onPressed: onLocate,
                  icon: const Icon(Symbols.location_on),
                ),
                const SizedBox(width: 8),
              ],
            ),
            for (final line in match.lines)
              InkWell(
                onTap: onLocate,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(formatLyricTimestamp(line.startMs)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(color: scheme.onSurface),
                            children: _highlightedSpans(scheme, line.text),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
