import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/artist_name_normalizer.dart';
import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:flutter/painting.dart';

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

  Artist? artistForName(String rawName) {
    final canonicalName =
        artistAliases[rawName] ?? normalizeArtistName(rawName);
    return artistCollection[canonicalName];
  }

  List<Artist> artistsForAudio(Audio audio) => _canonicalArtistNames(audio)
      .map((canonicalName) => artistCollection[canonicalName]!)
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
      scanRoots: rootsJson?.whereType<String>() ?? const [],
    ).._buildCollections();
    _instance = loaded;
  }

  void _buildCollections() {
    audioCollection.clear();
    artistCollection.clear();
    albumCollection.clear();
    artistAliases.clear();

    for (var f in folders) {
      audioCollection.addAll(f.audios);
    }

    for (Audio audio in audioCollection) {
      for (String rawName in audio.splitedArtists) {
        final canonicalName = normalizeArtistName(rawName);
        artistAliases[rawName] = canonicalName;
      }

      for (final canonicalName in _canonicalArtistNames(audio)) {
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

      /// 如果albumCollection中有audio.album指向的album，putIfAbsent会返回该album。
      /// 随后往这个album里添加该audio。
      ///
      /// 如果没有，创建一个名字为audio.album的空艺术家，并将audio.album与之相连。
      /// 随后往这个album里添加该audio。
      albumCollection
          .putIfAbsent(audio.album, () => Album(name: audio.album))
          .works
          .add(audio);
    }

    /// 将艺术家和专辑链接起来
    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.album,
          () => albumCollection[audio.album]!,
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
  }

  @override
  String toString() {
    return folders.toString();
  }
}

Iterable<String> _canonicalArtistNames(Audio audio) sync* {
  final seen = <String>{};
  for (final rawName in audio.splitedArtists) {
    final canonicalName = normalizeArtistName(rawName);
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

  ImageProvider? _cover;

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
    this.by,
  ) : splitedArtists = artist.split(
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
      );

  Map toMap() => {
        "title": title,
        "artist": artist,
        "album": album,
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
  }) async {
    final ratio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    return getPictureFromPath(
      path: path,
      width: (width * ratio).round(),
      height: (height * ratio).round(),
    ).then((pic) {
      if (pic == null) return null;

      return MemoryImage(pic);
    });
  }

  /// 缓存ImageProvider而不是Uint8List（bytes）
  /// 缓存bytes时，每次加载图片都要重新解码，内存占用很大。快速滚动时能到700mb
  /// 缓存ImageProvider不用重新解码。快速滚动时最多250mb
  /// 48*48
  Future<ImageProvider?> get cover {
    if (_cover == null) {
      return _getResizedPic(width: 48, height: 48).then((value) {
        if (value == null) return null;

        _cover = value;
        return _cover;
      });
    }
    return Future.value(_cover);
  }

  /// audio detail page 不需要频繁调用，所以不缓存图片
  /// 200 * 200
  Future<ImageProvider?> get mediumCover =>
      _getResizedPic(width: 200, height: 200);

  /// now playing 不需要频繁调用，所以不缓存图片
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

  /// 参与的艺术家
  Map<String, Artist> artistsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在album detail page
  /// 200*200
  Future<ImageProvider?> get cover =>
      works.first._getResizedPic(width: 200, height: 200);

  Album({required this.name});
}
