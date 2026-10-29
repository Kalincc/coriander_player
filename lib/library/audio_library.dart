import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/artist_name_normalizer.dart';
import 'package:coriander_player/library/audio_path_key.dart';
import 'package:coriander_player/library/artwork_cache.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/widgets.dart';

final _artworkCache = ArtworkCache(load: (path, width, height) async {
  final picture =
      await getPictureFromPath(path: path, width: width, height: height);
  return picture == null ? null : MemoryImage(picture);
});

/// Library consumers opt in to rebuilds without recreating the router or routes.
class AudioLibraryScope extends InheritedNotifier<ValueNotifier<int>> {
  AudioLibraryScope({super.key, required super.child})
      : super(notifier: AudioLibrary.revision);
}

/// from index.json
class AudioLibrary {
  List<AudioFolder> folders;
  final List<String> scanRoots;

  AudioLibrary._(this.folders, {Iterable<String> scanRoots = const []})
      : scanRoots = List.unmodifiable(scanRoots);

  AudioLibrary.forTesting(Iterable<Audio> audios)
      : folders = [AudioFolder(audios.toList(), '', 0, 0)],
        scanRoots = const [] {
    _buildCollections();
  }

  /// 所有音乐
  List<Audio> audioCollection = [];

  Map<String, Artist> artistCollection = {};

  Map<String, String> artistAliases = {};

  Map<String, Album> albumCollection = {};
  final Map<String, Audio> _audiosByPath = {};

  static final revision = ValueNotifier(0);

  static AudioLibrary watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AudioLibraryScope>();
    return instance;
  }

  Audio? audioForPath(String path) => _audiosByPath[audioPathKey(path)];

  AudioFolder? folderForPath(String path) => folders
      .where((folder) => audioPathKey(folder.path) == audioPathKey(path))
      .firstOrNull;

  Album? albumForAudio(Audio audio) =>
      albumCollection[(audioForPath(audio.path) ?? audio).albumKey];

  Album? refreshedAlbum(Album previous) {
    final sameAlbum = albumCollection[previous.id];
    if (sameAlbum != null) return sameAlbum;
    for (final work in previous.works) {
      final current = audioForPath(work.path);
      if (current != null) return albumForAudio(current);
    }
    return null;
  }

  Artist? refreshedArtist(Artist previous) {
    final sameName = artistForName(previous.name);
    if (sameName != null) return sameName;
    for (final work in previous.works) {
      final current = audioForPath(work.path);
      if (current == null) continue;
      final wasAlbumArtist = work.albumArtistNames.contains(previous.name);
      final oldNames = wasAlbumArtist
          ? work.albumArtistNames
          : _canonicalArtistNames(work).toList();
      final newNames = wasAlbumArtist
          ? current.albumArtistNames
          : _canonicalArtistNames(current).toList();
      final renamed =
          newNames.where((name) => !oldNames.contains(name)).toList();
      // Only follow an unambiguous rename; never redirect to a co-performer.
      if (renamed.length == 1) return artistForName(renamed.single);
    }
    return null;
  }

  Artist? artistForName(String rawName) {
    final canonicalName =
        artistAliases[rawName] ?? normalizeArtistName(rawName.trim());
    return artistCollection[canonicalName];
  }

  List<Artist> artistsForAudio(Audio audio) => _canonicalArtistNames(audio)
      .map((canonicalName) => artistCollection[canonicalName])
      .whereType<Artist>()
      .toList(growable: false);

  /// must call [initFromIndex]
  static AudioLibrary get instance {
    _instance ??= AudioLibrary._([]);
    return _instance!;
  }

  static AudioLibrary? _instance;

  /// 目前 index 结构：
  /// ```json
  /// {
  ///     "folders": [
  ///         {
  ///             "audios": [
  ///                 {...},
  ///                 ...
  ///             ],
  ///             ...
  ///         },
  ///         ...
  ///     ],
  ///     "version": 110
  /// }
  /// ```
  static Future<void> initFromIndex({File? indexFile}) async {
    final file = indexFile ??
        File(
            '${(await getAppDataDir()).path}${Platform.pathSeparator}index.json');
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Invalid library index envelope');
    }

    final foldersJson = decoded['folders'];
    if (foldersJson is! List) {
      throw const FormatException('Invalid library folders');
    }
    final rootsJson = decoded['roots'];
    if (rootsJson != null && rootsJson is! List) {
      throw const FormatException('Invalid library scan roots');
    }
    final scanRoots = <String>[];
    if (rootsJson is List) {
      for (final root in rootsJson) {
        if (root is! String || root.trim().isEmpty) {
          throw const FormatException('Invalid library scan root');
        }
        scanRoots.add(root);
      }
    }

    final folders = <AudioFolder>[];
    for (final encodedFolder in foldersJson) {
      if (encodedFolder is! Map || encodedFolder['audios'] is! List) {
        throw const FormatException('Invalid library folder');
      }
      final audios = <Audio>[];
      for (final encodedAudio in encodedFolder['audios'] as List) {
        if (encodedAudio is! Map) {
          throw const FormatException('Invalid library audio');
        }
        audios.add(Audio.fromMap(encodedAudio));
      }
      folders.add(AudioFolder.fromMap(encodedFolder, audios));
    }

    final loaded = AudioLibrary._(
      folders,
      scanRoots: scanRoots,
    ).._buildCollections();
    _artworkCache.clear();
    _instance = loaded;
    revision.value++;
  }

  void _buildCollections() {
    audioCollection.clear();
    artistCollection.clear();
    albumCollection.clear();
    artistAliases.clear();
    _audiosByPath.clear();

    for (var f in folders) {
      audioCollection.addAll(f.audios);
    }

    for (Audio audio in audioCollection) {
      _audiosByPath[audioPathKey(audio.path)] = audio;
      for (String rawName in audio.splitedArtists) {
        final canonicalName = normalizeArtistName(rawName.trim());
        artistAliases[rawName] = canonicalName;
      }

      for (final canonicalName in {
        ..._canonicalArtistNames(audio),
        ...audio.albumArtistNames,
      }) {
        /// 如果artistCollection中有artistName指向的artist，putIfAbsent会返回该artist。
        /// 随后往这个artist里添加该audio。
        ///
        /// 如果没有，创建一个名字为artistName的空艺术家，并将artistName与之相连。
        /// 随后往这个artist里添加该audio。
        artistCollection
            .putIfAbsent(canonicalName, () => Artist(name: canonicalName))
            .works
            .add(audio);
      }

      albumCollection
          .putIfAbsent(
            audio.albumKey,
            () => Album(
              name: audio.album,
              id: audio.albumKey,
              albumArtist: audio.effectiveAlbumArtist,
              albumArtistNames: audio.albumArtistNames.toSet(),
            ),
          )
          .works
          .add(audio);
    }

    /// 将艺术家和专辑链接起来
    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.albumKey,
          () => albumCollection[audio.albumKey]!,
        );
      }
    }

    /// 将专辑和艺术家链接起来
    for (Album album in albumCollection.values) {
      for (Audio audio in album.works) {
        for (final canonicalName in _canonicalArtistNames(audio)) {
          album.artistsMap.putIfAbsent(
            canonicalName,
            () => artistCollection[canonicalName]!,
          );
        }
      }
    }
  }

  void rebuildCollections() {
    _buildCollections();
    if (identical(this, _instance)) {
      _artworkCache.clear();
      revision.value++;
    }
  }

  @override
  String toString() {
    return folders.toString();
  }
}

Iterable<String> _canonicalArtistNames(Audio audio) sync* {
  final seen = <String>{};
  for (final rawName in audio.splitedArtists) {
    final canonicalName = normalizeArtistName(rawName.trim());
    if (seen.add(canonicalName)) {
      yield canonicalName;
    }
  }
}

class AudioFolder {
  List<Audio> audios;

  /// absolute path
  String path;

  /// secs since UNIX EPOCH
  int modified;

  /// secs since UNIX EPOCH
  int latest;

  AudioFolder(this.audios, this.path, this.modified, this.latest);

  factory AudioFolder.fromMap(Map map, List<Audio> audios) =>
      AudioFolder(audios, map["path"], map["modified"], map["latest"]);

  @override
  String toString() {
    return {
      "audios": audios.toString(),
      "path": path,
      "modified":
          DateTime.fromMillisecondsSinceEpoch(modified * 1000).toString(),
    }.toString();
  }
}

class Audio {
  String title;

  /// 从音乐标签中读取的艺术家字符串，可能包含多个艺术家，以“、”，“/”等分隔。
  String artist;

  /// 分割[artist]得到的结果
  List<String> splitedArtists;

  String album;

  String? albumArtist;

  /// 0 means the tag was absent; do not invent a disc number.
  int disc;
  int discTotal;

  String get effectiveAlbumArtist =>
      albumArtist?.trim().isNotEmpty == true ? albumArtist!.trim() : artist;

  List<String> get albumArtistNames => effectiveAlbumArtist
      .split(RegExp(AppSettings.instance.artistSplitPattern))
      .map((name) => normalizeArtistName(name.trim()))
      .toSet()
      .toList()
    ..sort();

  String get albumKey => jsonEncode([album.trim(), albumArtistNames]);

  String trackLabel({bool includeDisc = false}) {
    final number = track > 0 ? track.toString().padLeft(2, '0') : '--';
    return includeDisc ? 'CD${disc > 0 ? disc : '?'} · $number' : number;
  }

  /// 0: 没有track
  int track;

  /// audio's duration in secs
  int duration;

  /// kbps
  int? bitrate;

  int? sampleRate;

  /// absolute path
  String path;

  /// secs since UNIX EPOCH
  int modified;

  /// secs since UNIX EPOCH
  int created;

  /// 标签来源（Lofty、Windows、null）
  String? by;

  /// 以“、”和“/”分割艺术家，会把名称中带有这些符号的艺术家分割。
  /// 暂时想不到别的方法。
  Audio(
    this.title,
    this.artist,
    this.album,
    this.track,
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.path,
    this.modified,
    this.created,
    this.by, {
    this.albumArtist,
    this.disc = 0,
    this.discTotal = 0,
  }) : splitedArtists = artist.split(
          RegExp(AppSettings.instance.artistSplitPattern),
        );

  factory Audio.fromMap(Map map) => Audio(
        map["title"],
        map["artist"],
        map["album"],
        map["track"] ?? 0,
        map["duration"] ?? 0,
        map["bitrate"],
        map["sample_rate"],
        map["path"],
        map["modified"],
        map["created"],
        map["by"],
        albumArtist: map['album_artist'],
        disc: map['disc'] ?? 0,
        discTotal: map['disc_total'] ?? 0,
      );

  Map toMap() => {
        "title": title,
        "artist": artist,
        "album": album,
        'album_artist': albumArtist,
        'disc': disc,
        'disc_total': discTotal,
        "track": track,
        "duration": duration,
        "bitrate": bitrate,
        "sample_rate": sampleRate,
        "path": path,
        "modified": modified,
        "created": created,
        "by": by
      };

  /// 读取音乐文件的图片，自动适应缩放
  Future<ImageProvider?> _getResizedPic({
    required int width,
    required int height,
  }) {
    final ratio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    return _artworkCache.get(
      path: path,
      modified: modified,
      created: created,
      width: (width * ratio).round(),
      height: (height * ratio).round(),
    );
  }

  /// 共享最近 256 个尺寸/文件版本的 Future，避免每首歌永久持有封面。
  Future<ImageProvider?> get cover => _getResizedPic(width: 48, height: 48);

  /// 200 * 200
  Future<ImageProvider?> get mediumCover =>
      _getResizedPic(width: 200, height: 200);

  /// size: 400 * devicePixelRatio（屏幕缩放大小）
  Future<ImageProvider?> get largeCover =>
      _getResizedPic(width: 400, height: 400);

  @override
  String toString() {
    return {
      "title": title,
      "artist": artist,
      "album": album,
      "path": path,
      "modified":
          DateTime.fromMillisecondsSinceEpoch(modified * 1000).toString(),
      "created": DateTime.fromMillisecondsSinceEpoch(created * 1000).toString(),
    }.toString();
  }
}

class Artist {
  String name;

  /// 所有专辑
  Map<String, Album> albumsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在artist detail page
  /// 200*200
  Future<ImageProvider?> get picture =>
      works.first._getResizedPic(width: 200, height: 200);

  Artist({required this.name});
}

class Album {
  String name;
  final String id;
  final String albumArtist;
  final Set<String> albumArtistNames;

  bool get hasMultipleDiscs => works.any((a) => a.disc > 1 || a.discTotal > 1);

  /// 参与的艺术家
  Map<String, Artist> artistsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在album detail page
  /// 200*200
  Future<ImageProvider?> get cover =>
      works.first._getResizedPic(width: 200, height: 200);

  Album({
    required this.name,
    String? id,
    this.albumArtist = '',
    this.albumArtistNames = const {},
  }) : id = id ?? name;
}

int compareAlbumTracks(Audio a, Audio b) {
  final byDisc = a.disc.compareTo(b.disc);
  if (byDisc != 0) return byDisc;
  final byTrack = a.track.compareTo(b.track);
  return byTrack != 0 ? byTrack : a.path.compareTo(b.path);
}
