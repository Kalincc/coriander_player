import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/app_paths.dart' as app_paths;
import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_path_key.dart';
import 'package:coriander_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:coriander_player/page/now_playing_page/page.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/play_service/playback_service.dart';
import 'package:coriander_player/lyric/lyric_timing.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

class PagePreference {
  int sortMethod;
  SortOrder sortOrder;
  ContentView contentView;

  PagePreference(this.sortMethod, this.sortOrder, this.contentView);

  Map toMap() => {
        "sortMethod": sortMethod,
        "sortOrder": sortOrder.name,
        "contentView": contentView.name,
      };

  factory PagePreference.fromMap(Map map) => PagePreference(
        map["sortMethod"] ?? 0,
        SortOrder.fromString(map["sortOrder"]) ?? SortOrder.ascending,
        ContentView.fromString(map["contentView"]) ?? ContentView.list,
      );
}

enum SpectrumStyle {
  off('关闭'),
  bars('柱状图'),
  mirror('镜像反射'),
  circle('圆形');

  const SpectrumStyle(this.label);
  final String label;
}

typedef SpectrumOptions = ({SpectrumStyle style, bool particles});

class NowPlayingPagePreference extends ChangeNotifier {
  NowPlayingViewMode nowPlayingViewMode;
  LyricTextAlign lyricTextAlign;
  double lyricFontSize;
  double translationFontSize;
  int lyricOffsetMs;
  bool showTranslation;
  final ValueNotifier<SpectrumOptions> spectrum;
  final Map<String, int> _lyricOffsetsByPath;
  String? _activeAudioPath;

  NowPlayingPagePreference(
    this.nowPlayingViewMode,
    this.lyricTextAlign,
    this.lyricFontSize,
    this.translationFontSize, {
    int lyricOffsetMs = 0,
    this.showTranslation = true,
    Map<String, int> lyricOffsetsByPath = const {},
    SpectrumOptions spectrum = (style: SpectrumStyle.off, particles: true),
  })  : spectrum = ValueNotifier(spectrum),
        lyricOffsetMs = clampLyricOffsetMs(lyricOffsetMs),
        _lyricOffsetsByPath = {
          for (final entry in lyricOffsetsByPath.entries)
            audioPathKey(entry.key): clampLyricOffsetMs(entry.value),
        };

  Map toMap() => {
        "nowPlayingViewMode": nowPlayingViewMode.name,
        "lyricTextAlign": lyricTextAlign.name,
        "lyricFontSize": lyricFontSize,
        "translationFontSize": translationFontSize,
        "lyricOffsetMs": lyricOffsetMs,
        "showTranslation": showTranslation,
        "spectrumStyle": spectrum.value.style.name,
        "spectrumParticles": spectrum.value.particles,
        "lyricOffsetsByPath": Map<String, int>.from(_lyricOffsetsByPath),
      };

  factory NowPlayingPagePreference.fromMap(Map map) {
    final rawOffset = map["lyricOffsetMs"];
    final rawShowTranslation = map["showTranslation"];
    final rawParticles = map['spectrumParticles'];
    return NowPlayingPagePreference(
      NowPlayingViewMode.fromString(map["nowPlayingViewMode"]) ??
          NowPlayingViewMode.withLyric,
      LyricTextAlign.fromString(map["lyricTextAlign"]) ?? LyricTextAlign.left,
      map["lyricFontSize"] ?? 22.0,
      map["translationFontSize"] ?? 18.0,
      lyricOffsetMs:
          rawOffset is num ? clampLyricOffsetMs(rawOffset.toInt()) : 0,
      showTranslation: rawShowTranslation is bool ? rawShowTranslation : true,
      spectrum: (
        style: SpectrumStyle.values.firstWhere(
          (style) => style.name == map['spectrumStyle'],
          orElse: () => SpectrumStyle.off,
        ),
        particles: rawParticles is bool ? rawParticles : true,
      ),
      lyricOffsetsByPath: {
        if (map['lyricOffsetsByPath'] is Map)
          for (final entry in (map['lyricOffsetsByPath'] as Map).entries)
            if (entry.key is String &&
                entry.value is num &&
                (entry.value as num).isFinite)
              entry.key as String: (entry.value as num).toInt(),
      },
    );
  }

  void setLyricOffsetMs(int value) {
    final clampedValue = clampLyricOffsetMs(value);
    if (lyricOffsetMs == clampedValue) return;
    lyricOffsetMs = clampedValue;
    final path = _activeAudioPath;
    if (path != null) {
      if (clampedValue == 0) {
        _lyricOffsetsByPath.remove(path);
      } else {
        _lyricOffsetsByPath[path] = clampedValue;
      }
    }
    notifyListeners();
  }

  void bindAudioPath(String? path) {
    final key = path == null ? null : audioPathKey(path);
    if (_activeAudioPath == key) return;
    _activeAudioPath = key;
    lyricOffsetMs = _lyricOffsetsByPath[key] ?? 0;
    notifyListeners();
  }

  void setShowTranslation(bool value) {
    if (showTranslation == value) return;
    showTranslation = value;
    notifyListeners();
  }

  @override
  void dispose() {
    spectrum.dispose();
    super.dispose();
  }
}

class PlaybackPreference {
  PlayMode playMode;
  double volumeDsp;

  PlaybackPreference(this.playMode, this.volumeDsp);

  Map toMap() => {
        "playMode": playMode.name,
        "volumeDsp": volumeDsp,
      };

  factory PlaybackPreference.fromMap(Map map) => PlaybackPreference(
        PlayMode.fromString(map["playMode"]) ?? PlayMode.forward,
        map["volumeDsp"] ?? 1.0,
      );
}

class AppPreference {
  var audiosPagePref = PagePreference(0, SortOrder.ascending, ContentView.list);

  var artistsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.table);

  var artistDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var albumsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.table);
  bool albumCoverWall = false;

  var albumDetailPagePref =
      PagePreference(2, SortOrder.ascending, ContentView.list);

  var foldersPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var folderDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var playlistsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var playlistDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  String startPage = app_paths.AUDIOS_PAGE;
  final recentSearches = ValueNotifier<List<String>>(const []);

  void rememberSearch(String query) {
    final term = query.trim();
    if (term.isEmpty) return;
    recentSearches.value = List.unmodifiable([
      term,
      ...recentSearches.value
          .where((item) => item.toLowerCase() != term.toLowerCase())
          .take(7),
    ]);
  }

  var playbackPref = PlaybackPreference(PlayMode.forward, 1.0);

  var nowPlayingPagePref = NowPlayingPagePreference(
      NowPlayingViewMode.withLyric, LyricTextAlign.left, 22.0, 18.0);

  Future<void> _saveTail = Future.value();

  Future<void> save({bool rethrowOnError = false}) {
    final write = _saveTail.then((_) => _save(rethrowOnError: rethrowOnError));
    _saveTail = write.catchError((_) {});
    return write;
  }

  Future<void> _save({required bool rethrowOnError}) async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final appPreferencePath = "$supportPath\\app_preference.json";

      Map prefMap = {
        "audiosPagePref": audiosPagePref.toMap(),
        "artistsPagePref": artistsPagePref.toMap(),
        "artistDetailPagePref": artistDetailPagePref.toMap(),
        "albumsPagePref": albumsPagePref.toMap(),
        "albumCoverWall": albumCoverWall,
        "albumDetailPagePref": albumDetailPagePref.toMap(),
        "foldersPagePref": foldersPagePref.toMap(),
        "folderDetailPagePref": folderDetailPagePref.toMap(),
        "playlistsPagePref": playlistsPagePref.toMap(),
        "playlistDetailPagePref": playlistDetailPagePref.toMap(),
        "startPagePath": startPage,
        "startPage": startPage == app_paths.PLAYLISTS_PAGE
            ? 4
            : app_paths.START_PAGES.indexOf(startPage),
        "recentSearches": recentSearches.value,
        "playbackPref": playbackPref.toMap(),
        "nowPlayingPagePref": nowPlayingPagePref.toMap(),
      };

      final prefJson = json.encode(prefMap);
      final output = await File(appPreferencePath).create(recursive: true);
      await output.writeAsString(prefJson);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      if (rethrowOnError) rethrow;
    }
  }

  static Future<void> read() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final appPreferencePath = "$supportPath\\app_preference.json";

      final prefJson = await File(appPreferencePath).readAsString();
      final Map prefMap = json.decode(prefJson);

      instance.audiosPagePref =
          PagePreference.fromMap(prefMap["audiosPagePref"]);
      instance.artistsPagePref =
          PagePreference.fromMap(prefMap["artistsPagePref"]);
      instance.artistDetailPagePref = PagePreference.fromMap(
        prefMap["artistDetailPagePref"],
      );
      instance.albumsPagePref =
          PagePreference.fromMap(prefMap["albumsPagePref"]);
      instance.albumCoverWall = prefMap["albumCoverWall"] == true;
      instance.albumDetailPagePref = PagePreference.fromMap(
        prefMap["albumDetailPagePref"],
      );
      instance.foldersPagePref =
          PagePreference.fromMap(prefMap["foldersPagePref"]);
      instance.folderDetailPagePref = PagePreference.fromMap(
        prefMap["folderDetailPagePref"],
      );
      instance.playlistsPagePref = PagePreference.fromMap(
        prefMap["playlistsPagePref"],
      );
      instance.playlistDetailPagePref = PagePreference.fromMap(
        prefMap["playlistDetailPagePref"],
      );
      instance.startPage = app_paths.restoreStartPage(
          prefMap['startPagePath'], prefMap['startPage']);
      final recent = prefMap['recentSearches'];
      instance.recentSearches.value = recent is List
          ? List.unmodifiable(recent
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .take(8))
          : const [];
      instance.playbackPref =
          PlaybackPreference.fromMap(prefMap["playbackPref"]);
      instance.nowPlayingPagePref =
          NowPlayingPagePreference.fromMap(prefMap["nowPlayingPagePref"]);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  static final AppPreference instance = AppPreference();
}
