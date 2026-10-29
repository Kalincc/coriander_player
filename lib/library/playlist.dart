// ignore_for_file: non_constant_identifier_names

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/library/audio_path_key.dart';
import 'package:coriander_player/library/local_json_store.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/foundation.dart';

const likedPlaylistName = '我喜欢';
const _playlistsFileName = 'playlists.json';
const _playlistsVersion = 1;

bool isReservedPlaylistName(String name) => name.trim() == likedPlaylistName;

List<Playlist> PLAYLISTS = [];
final playlistRevision = ValueNotifier(0);
final _failedPlaylistStores = <String>{};
final _loadingPlaylistStores = <String>{};
// ponytail: one app-wide queue; split by store only for multiple active stores.
Future<void> _playlistSaveChain = Future.value();

Future<void> readPlaylists({LocalJsonStore? store}) async {
  final localStore = store ?? await _defaultStore();
  final storePath = audioPathKey(localStore.directory.absolute.path);
  if (!_loadingPlaylistStores.add(storePath)) {
    throw StateError('Playlists are already loading');
  }

  try {
    await _playlistSaveChain;
    var legacyFormat = false;
    final loaded = await localStore.readValidated<List<Playlist>>(
      _playlistsFileName,
      (saved) {
        final parsed = _playlistItemsFromSavedJson(saved);
        legacyFormat = saved is List;
        return parsed;
      },
    );
    final next = loaded ?? <Playlist>[];
    var shouldSave = loaded == null || legacyFormat;
    if (_normalizeLikedPlaylist(next)) {
      shouldSave = true;
    }
    _failedPlaylistStores.remove(storePath);
    if (shouldSave) await _writePlaylists(localStore, next);
    PLAYLISTS
      ..clear()
      ..addAll(next);
    playlistRevision.value++;
  } catch (err, trace) {
    _failedPlaylistStores.add(storePath);
    LOGGER.e(err, stackTrace: trace);
    rethrow;
  } finally {
    _loadingPlaylistStores.remove(storePath);
  }
}

Future<void> savePlaylists({
  LocalJsonStore? store,
  bool rethrowOnError = false,
}) async {
  try {
    final localStore = store ?? await _defaultStore();
    if (_loadingPlaylistStores
        .contains(audioPathKey(localStore.directory.absolute.path))) {
      throw StateError('Playlists are still loading');
    }
    await _writePlaylists(localStore, PLAYLISTS);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    if (rethrowOnError) rethrow;
  }
}

Future<void> _writePlaylists(LocalJsonStore store, List<Playlist> playlists) {
  final snapshot = {
    'version': _playlistsVersion,
    'playlists': playlists.map((item) => item.toMap()).toList(),
  };
  final write = _playlistSaveChain.then((_) {
    if (_failedPlaylistStores
        .contains(audioPathKey(store.directory.absolute.path))) {
      throw StateError('Playlists must be loaded successfully before saving');
    }
    return store.writeAtomically(_playlistsFileName, snapshot);
  });
  _playlistSaveChain = write.catchError((_) {});
  return write;
}

Future<void> ensureLikedPlaylist() async {
  _normalizeLikedPlaylist();
}

bool isLiked(Audio audio) {
  for (final playlist in PLAYLISTS) {
    if (playlist.name == likedPlaylistName) {
      return playlist.audios.keys.any(
        (path) => audioPathKey(path) == audioPathKey(audio.path),
      );
    }
  }
  return false;
}

Future<void> toggleLiked(Audio audio, {LocalJsonStore? store}) async {
  await ensureLikedPlaylist();
  final liked = PLAYLISTS.singleWhere(
    (playlist) => playlist.name == likedPlaylistName,
  );
  if (isLiked(audio)) {
    removeAudioFromPlaylist(liked, audio.path);
  } else {
    addAudioToPlaylist(liked, audio);
  }
  await savePlaylists(store: store);
}

bool addAudioToPlaylist(Playlist playlist, Audio audio) {
  if (playlist.audios.keys.any(
    (path) => audioPathKey(path) == audioPathKey(audio.path),
  )) {
    return false;
  }
  playlist.audios[audio.path] = audio;
  playlistRevision.value++;
  return true;
}

bool removeAudioFromPlaylist(Playlist playlist, String path) {
  final aliases = playlist.audios.keys
      .where((saved) => audioPathKey(saved) == audioPathKey(path))
      .toList();
  if (aliases.isEmpty) return false;
  for (final alias in aliases) {
    playlist.audios.remove(alias);
  }
  playlistRevision.value++;
  return true;
}

Future<void> reconcilePlaylistAudios(
  Iterable<Audio> library, {
  LocalJsonStore? store,
  bool removeMissing = true,
}) async {
  final available = {
    for (final audio in library) audioPathKey(audio.path): audio
  };
  var changed = false;
  for (final playlist in PLAYLISTS) {
    final reconciled = <String, Audio>{};
    for (final entry in playlist.audios.entries) {
      final current = available[audioPathKey(entry.key)];
      if (current == null) {
        if (removeMissing) {
          changed = true;
        } else {
          reconciled[entry.key] = entry.value;
        }
        continue;
      }
      reconciled[current.path] = current;
      if (entry.key != current.path || !identical(entry.value, current)) {
        changed = true;
      }
    }
    playlist.audios = reconciled;
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

List<Playlist> _playlistItemsFromSavedJson(Object? saved) {
  final Object? items = saved is List
      ? saved
      : saved is Map && saved['version'] == _playlistsVersion
          ? saved['playlists']
          : null;
  if (items is! List) {
    throw const FormatException('Invalid playlists JSON');
  }
  return items.map((item) {
    if (item is! Map) {
      throw const FormatException('Invalid playlist');
    }
    return Playlist.fromMap(item);
  }).toList();
}

bool _normalizeLikedPlaylist([List<Playlist>? playlists]) {
  final target = playlists ?? PLAYLISTS;
  final indexes = <int>[];
  final mergedAudios = <String, Audio>{};

  for (var index = 0; index < target.length; index++) {
    final playlist = target[index];
    if (playlist.name == likedPlaylistName) {
      indexes.add(index);
      for (final audio in playlist.audios.values) {
        mergedAudios[audio.path] = audio;
      }
    }
  }

  if (indexes.isEmpty) {
    target.add(Playlist(likedPlaylistName, {}, isSystem: true));
    return true;
  }

  final existing = target[indexes.first];
  if (indexes.length == 1 &&
      existing.isSystem &&
      _sameAudioPaths(existing.audios, mergedAudios)) {
    return false;
  }

  for (final index in indexes.reversed) {
    target.removeAt(index);
  }
  target.insert(
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
    final name = map['name'];
    final audioMaps = map['audios'];
    if (name is! String ||
        audioMaps is! List ||
        (map.containsKey('isSystem') && map['isSystem'] is! bool)) {
      throw const FormatException('Invalid playlist');
    }
    for (final item in audioMaps) {
      if (item is! Map) {
        throw const FormatException('Invalid playlist audio');
      }
      try {
        final audio = Audio.fromMap(item);
        if (audio.path.isEmpty) {
          throw const FormatException('Invalid playlist audio path');
        }
        audios[audio.path] = audio;
      } on TypeError {
        throw const FormatException('Invalid playlist audio');
      }
    }
    return Playlist._(
      name,
      audios,
      isSystem: map['isSystem'] == true,
    );
  }
}
