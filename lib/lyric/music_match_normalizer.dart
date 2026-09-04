import 'package:coriander_player/library/audio_library.dart';
import 'package:pinyin/pinyin.dart';

class MusicMatchScore {
  final double value;
  final List<String> reasons;
  const MusicMatchScore(this.value, this.reasons);
}

final _punctuation = RegExp(r'''[\p{P}\p{S}]+''', unicode: true);
final _trackNumber = RegExp(r'^\s*\d{1,3}(?:\s*[.\-、)]\s*|\s+)');
final _versionWords = RegExp(
  r'\b(?:feat\.?|ft\.?|with|live|remix|acoustic|radio|studio|original|edit|version|remaster|instrumental|karaoke|demo)\b|伴奏|现场',
  caseSensitive: false,
);
final _bracketed = RegExp(r'''[\(\[\{（【][^\)\]\}）】]+[\)\]\}）】]''');

String _basic(String text) => ChineseHelper.convertToSimplifiedChinese(
      text.trim().toLowerCase().replaceAll(_punctuation, ' ').replaceAll(
            RegExp(r'\s+'),
            ' ',
          ),
    );

String _titleCore(String title) {
  var value = _basic(title.replaceAll(_bracketed, ''));
  value = value.replaceFirst(_trackNumber, '');
  // Version markers and feat artist names are suffix metadata for searching.
  value = value.replaceFirst(
      RegExp(r'\s+(?:feat|ft|with)\b.*$', caseSensitive: false), '');
  value = value.replaceFirst(
      RegExp(r'\s+(?:live|remix|伴奏|现场)\b.*$', caseSensitive: false), '');
  return value.trim();
}

Set<String> _versions(String text) {
  final versions = _versionWords
      .allMatches(text)
      .map((m) => m.group(0)!.toLowerCase().replaceAll('.', ''))
      .toSet();
  for (final match in _bracketed.allMatches(text)) {
    versions
        .addAll(_basic(match.group(0)!).split(' ').where((e) => e.isNotEmpty));
  }
  return versions;
}

List<String> _forms(String text) {
  final simplified = _basic(text);
  if (simplified.isEmpty) return const [];
  final pinyinText =
      PinyinHelper.getPinyin(simplified, separator: ' ').trim().toLowerCase();
  return {simplified, pinyinText, pinyinText.replaceAll(' ', '')}
      .where((e) => e.isNotEmpty)
      .toList();
}

double _similarity(String expected, String actual) {
  final a = _forms(expected);
  final b = _forms(actual);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a.any((x) => b.contains(x))) return 1;
  if (a.any((x) => b.any((y) => x.contains(y) || y.contains(x)))) return .7;
  final at = _basic(expected).split(' ').where((x) => x.isNotEmpty).toSet();
  final bt = _basic(actual).split(' ').where((x) => x.isNotEmpty).toSet();
  if (at.isEmpty || bt.isEmpty) return 0;
  return at.intersection(bt).length / at.union(bt).length;
}

String _queryTitle(String title) => _titleCore(title);

List<String> musicSearchQueriesFor(Audio audio) {
  final title = _queryTitle(audio.title);
  final artist = _basic(audio.artist);
  final album = _basic(audio.album);
  return <String>{
    if (title.isNotEmpty && artist.isNotEmpty) '$title $artist',
    title,
    if (title.isNotEmpty && album.isNotEmpty) '$title $album',
  }.toList();
}

MusicMatchScore scoreMusicCandidate(
  Audio audio, {
  required String title,
  required String artists,
  required String album,
  int? durationSeconds,
}) {
  final titleScore = _similarity(_titleCore(audio.title), _titleCore(title));
  final artistScore = _similarity(audio.artist, artists);
  final albumScore = _similarity(audio.album, album);
  final durationScore = durationSeconds == null || audio.duration <= 0
      ? 0
      : (audio.duration - durationSeconds).abs() <= 2
          ? 1
          : (audio.duration - durationSeconds).abs() <= 5
              ? .5
              : 0;
  final expectedVersions = _versions(audio.title);
  final candidateVersions = _versions(title);
  var adjustment = 0.0;
  final reasons = <String>[];
  if (expectedVersions.isNotEmpty &&
      expectedVersions.length == candidateVersions.length &&
      expectedVersions.containsAll(candidateVersions)) {
    adjustment = .05;
    reasons.add('版本匹配');
  } else if (expectedVersions.length != candidateVersions.length ||
      expectedVersions.difference(candidateVersions).isNotEmpty ||
      candidateVersions.difference(expectedVersions).isNotEmpty) {
    adjustment = -.20;
    reasons.add('版本不一致');
  }
  if (titleScore == 1) reasons.add('标题一致');
  if (artistScore == 1) reasons.add('歌手一致');
  final value = (titleScore * .60 +
          artistScore * .20 +
          albumScore * .10 +
          durationScore * .10 +
          adjustment)
      .clamp(0.0, 1.0);
  return MusicMatchScore(value.toDouble(), List.unmodifiable(reasons));
}

String musicCandidateKey({
  required String title,
  required String artists,
  required String album,
}) {
  final versions = _versions(title).toList()..sort();
  return [
    _titleCore(title),
    versions.join(' '),
    _basic(artists),
    _basic(album),
  ].join('\u001f');
}
