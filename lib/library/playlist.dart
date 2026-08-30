// ignore_for_file: non_constant_identifier_names

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

const likedPlaylistName = '我喜欢';
const _playlistsFileName = 'playlists.json';
const _playlistsVersion = 1;

bool isReservedPlaylistName(String name) => name.trim() == likedPlaylistName;

List<Playlist> PLAYLISTS = [];
final playlistRevision = ValueNotifier(0);

Future<void> readPlaylists({LocalJsonStore? store}) async {
  final localStore = store ?? await _defaultStore();
  var shouldSave = false;

  PLAYLISTS.clear();
  try {
    final saved = await localStore.read(_playlistsFileName);
    if (saved == null) {
      shouldSave = true;
    } else {
      final playlistsJson = _playlistItemsFromSavedJson(saved);
      shouldSave = saved is List;
      PLAYLISTS.addAll(playlistsJson.map(Playlist.fromMap));
    }
  } catch (err, trace) {
    PLAYLISTS.clear();
    LOGGER.e(err, stackTrace: trace);
  }

  if (_normalizeLikedPlaylist()) {
    shouldSave = true;
  }
  if (shouldSave) {
    await savePlaylists(store: localStore);
  }
  playlistRevision.value++;
}

Future<void> savePlaylists({
  LocalJsonStore? store,
  bool rethrowOnError = false,
}) async {
  try {
    final localStore = store ?? await _defaultStore();
    await localStore.writeAtomically(_playlistsFileName, {
      'version': _playlistsVersion,
      'playlists': PLAYLISTS.map((item) => item.toMap()).toList(),
    });
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    if (rethrowOnError) rethrow;
  }
}

Future<void> ensureLikedPlaylist() async {
  _normalizeLikedPlaylist();
}

bool isLiked(Audio audio) {
  for (final playlist in PLAYLISTS) {
    if (playlist.name == likedPlaylistName) {
      return playlist.audios.containsKey(audio.path);
    }
  }
  return false;
}

Future<void> toggleLiked(Audio audio, {LocalJsonStore? store}) async {
  await ensureLikedPlaylist();
  final liked = PLAYLISTS.singleWhere(
    (playlist) => playlist.name == likedPlaylistName,
  );
  if (liked.audios.containsKey(audio.path)) {
    removeAudioFromPlaylist(liked, audio.path);
  } else {
    addAudioToPlaylist(liked, audio);
  }
  await savePlaylists(store: store);
}

bool addAudioToPlaylist(Playlist playlist, Audio audio) {
  if (playlist.audios.containsKey(audio.path)) return false;
  playlist.audios[audio.path] = audio;
  playlistRevision.value++;
  return true;
}

bool removeAudioFromPlaylist(Playlist playlist, String path) {
  if (!playlist.audios.containsKey(path)) return false;
  playlist.audios.remove(path);
  playlistRevision.value++;
  return true;
}

Future<void> reconcilePlaylistAudios(
  Iterable<Audio> library, {
  LocalJsonStore? store,
}) async {
  final availablePaths = library.map((audio) => audio.path).toSet();
  var changed = false;
  for (final playlist in PLAYLISTS) {
    final deletedPaths = playlist.audios.keys
        .where((path) => !availablePaths.contains(path))
        .toList(growable: false);
    if (deletedPaths.isEmpty) continue;
    changed = true;
    for (final path in deletedPaths) {
      playlist.audios.remove(path);
    }
  }
  if (!changed) return;

  await savePlaylists(store: store);
  playlistRevision.value++;
}

bool removePlaylist(Playlist playlist) {
  if (playlist.isSystem) {
    return false;
  }
  return PLAYLISTS.remove(playlist);
}

bool createPlaylist(String name) {
  if (isReservedPlaylistName(name)) return false;
  PLAYLISTS.add(Playlist(name, {}));
  return true;
}

Future<LocalJsonStore> _defaultStore() async =>
    LocalJsonStore(await getAppDataDir());

Iterable<Map> _playlistItemsFromSavedJson(Object saved) {
  if (saved is List) {
    return saved.cast<Map>();
  }
  if (saved is Map) {
    final items = saved['playlists'];
    if (items is List) {
      return items.cast<Map>();
    }
  }
  throw const FormatException('Invalid playlists JSON');
}

bool _normalizeLikedPlaylist() {
  final indexes = <int>[];
  final mergedAudios = <String, Audio>{};

  for (var index = 0; index < PLAYLISTS.length; index++) {
    final playlist = PLAYLISTS[index];
    if (playlist.name == likedPlaylistName) {
      indexes.add(index);
      for (final audio in playlist.audios.values) {
        mergedAudios[audio.path] = audio;
      }
    }
  }

  if (indexes.isEmpty) {
    PLAYLISTS.add(Playlist(likedPlaylistName, {}, isSystem: true));
    return true;
  }

  final existing = PLAYLISTS[indexes.first];
  if (indexes.length == 1 &&
      existing.isSystem &&
      _sameAudioPaths(existing.audios, mergedAudios)) {
    return false;
  }

  for (final index in indexes.reversed) {
    PLAYLISTS.removeAt(index);
  }
  PLAYLISTS.insert(
    indexes.first,
    Playlist(likedPlaylistName, mergedAudios, isSystem: true),
  );
  return true;
}

bool _sameAudioPaths(Map<String, Audio> first, Map<String, Audio> second) {
  if (first.length != second.length) {
    return false;
  }
  return first.keys.every(second.containsKey);
}

class Playlist {
  factory Playlist(
    String name,
    Map<String, Audio> audios, {
    bool isSystem = false,
  }) {
    if (!isSystem && isReservedPlaylistName(name)) {
      throw ArgumentError.value(name, 'name', 'Reserved playlist name');
    }
    return Playlist._(name, audios, isSystem: isSystem);
  }

  Playlist._(this._name, this.audios, {required this.isSystem});

  String _name;

  String get name => _name;

  set name(String value) {
    if (!isSystem && !isReservedPlaylistName(value)) {
      _name = value;
    }
  }

  /// path, audio
  Map<String, Audio> audios;

  Audio? get latestAudio => audios.isEmpty ? null : audios.values.last;

  final bool isSystem;

  bool rename(String value) {
    if (isSystem || isReservedPlaylistName(value)) {
      return false;
    }
    _name = value;
    return true;
  }

  Map<String, Object> toMap() {
    final audioMaps = audios.values.map((item) => item.toMap()).toList();
    return {
      'name': name,
      'audios': audioMaps,
      'isSystem': isSystem,
    };
  }

  factory Playlist.fromMap(Map map) {
    final audios = <String, Audio>{};
    final audioMaps = map['audios'];
    if (audioMaps is List) {
      for (final item in audioMaps.whereType<Map>()) {
        final audio = Audio.fromMap(item);
        audios[audio.path] = audio;
      }
    }
    return Playlist._(
      map['name'] as String,
      audios,
      isSystem: map['isSystem'] == true,
    );
  }
}
