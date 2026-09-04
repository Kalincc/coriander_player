import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/lyric/online_lyric_models.dart';
import 'package:path/path.dart' as path;

class OnlineLyricCacheEntry {
  final String key;
  final String audioFingerprint;
  final OnlineLyricPayload payload;
  final String title;
  final String artists;
  final String album;
  final double score;
  final int fetchedAtMs;

  const OnlineLyricCacheEntry({
    required this.key,
    required this.audioFingerprint,
    required this.payload,
    required this.title,
    required this.artists,
    required this.album,
    required this.score,
    required this.fetchedAtMs,
  });

  Map<String, Object?> toJson() => {
        'audioFingerprint': audioFingerprint,
        'payload': {
          'format': payload.format.name,
          'lyricText': payload.lyricText,
          if (payload.translationText != null)
            'translationText': payload.translationText,
        },
        'title': title,
        'artists': artists,
        'album': album,
        'score': score,
        'fetchedAtMs': fetchedAtMs,
      };

  static OnlineLyricCacheEntry fromJson(
      String key, Map<Object?, Object?> json) {
    final payloadJson = json['payload'];
    if (payloadJson is! Map) {
      throw const FormatException('Invalid lyric payload');
    }
    final format = switch (payloadJson['format']) {
      'lrc' => OnlineLyricFormat.lrc,
      'krc' => OnlineLyricFormat.krc,
      'qrc' => OnlineLyricFormat.qrc,
      _ => throw const FormatException('Invalid lyric format'),
    };
    final audioFingerprint = json['audioFingerprint'];
    final lyricText = payloadJson['lyricText'];
    final title = json['title'];
    final artists = json['artists'];
    final album = json['album'];
    final score = json['score'];
    final fetchedAtMs = json['fetchedAtMs'];
    if (audioFingerprint is! String ||
        lyricText is! String ||
        title is! String ||
        artists is! String ||
        album is! String ||
        score is! num ||
        fetchedAtMs is! int) {
      throw const FormatException('Invalid lyric cache entry');
    }
    final translation = payloadJson['translationText'];
    if (translation != null && translation is! String) {
      throw const FormatException('Invalid lyric translation');
    }
    return OnlineLyricCacheEntry(
      key: key,
      audioFingerprint: audioFingerprint,
      payload: OnlineLyricPayload(format, lyricText, translation as String?),
      title: title,
      artists: artists,
      album: album,
      score: score.toDouble(),
      fetchedAtMs: fetchedAtMs,
    );
  }
}

class OnlineLyricCache {
  static const int formatVersion = 1;
  static const Duration ttl = Duration(days: 30);
  static final OnlineLyricCache _defaultCache = OnlineLyricCache(
    read: () async => readOnlineLyricCacheFromDirectory(
      await getAppDataDir(),
    ),
    write: (contents) async => writeOnlineLyricCacheAtomically(
      await getAppDataDir(),
      contents,
    ),
  );

  final Future<String?> Function() _read;
  final Future<void> Function(String contents) _write;
  final int maxEntries;
  final Map<String, OnlineLyricCacheEntry> _entries = {};
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writeTail = Future.value();

  OnlineLyricCache({
    required Future<String?> Function() read,
    required Future<void> Function(String contents) write,
    this.maxEntries = 200,
  })  : _read = read,
        _write = write;

  factory OnlineLyricCache.defaults() => _defaultCache;

  Future<OnlineLyricCacheEntry?> readEntry(
    String key, {
    required String audioFingerprint,
  }) async {
    await _load();
    final entry = _entries[key];
    if (entry == null || _isExpired(entry)) return null;
    if (audioFingerprint.isNotEmpty &&
        entry.audioFingerprint != audioFingerprint) {
      return null;
    }
    return entry;
  }

  Future<List<OnlineLyricCacheEntry>> readEntriesForAudioFingerprint(
    String audioFingerprint,
  ) async {
    await _load();
    final entries = _entries.values
        .where((entry) =>
            !_isExpired(entry) && entry.audioFingerprint == audioFingerprint)
        .toList()
      ..sort((a, b) {
        final scoreOrder = b.score.compareTo(a.score);
        if (scoreOrder != 0) return scoreOrder;
        final fetchedOrder = b.fetchedAtMs.compareTo(a.fetchedAtMs);
        return fetchedOrder != 0 ? fetchedOrder : a.key.compareTo(b.key);
      });
    return entries;
  }

  Future<void> writeEntry(OnlineLyricCacheEntry entry) {
    final result = _writeTail.then((_) => _writeEntry(entry));
    _writeTail = result.catchError((_) {});
    return result;
  }

  Future<void> _writeEntry(OnlineLyricCacheEntry entry) async {
    await _load();
    _entries[entry.key] = entry;
    _prune();
    await _write(jsonEncode({
      'version': formatVersion,
      'entries': {
        for (final item in _entries.entries) item.key: item.value.toJson(),
      },
    }));
  }

  Future<void> _load() =>
      _loaded ? Future.value() : (_loading ??= _readEntries());

  Future<void> _readEntries() async {
    try {
      final contents = await _read();
      if (contents == null) return;
      final envelope = jsonDecode(contents);
      if (envelope is! Map ||
          envelope.length != 2 ||
          envelope['version'] != formatVersion ||
          envelope['entries'] is! Map) {
        throw const FormatException('Invalid lyric cache envelope');
      }
      final loaded = <String, OnlineLyricCacheEntry>{};
      for (final item in (envelope['entries'] as Map).entries) {
        if (item.key is! String || item.value is! Map) {
          throw const FormatException('Invalid lyric cache entry');
        }
        loaded[item.key as String] = OnlineLyricCacheEntry.fromJson(
          item.key as String,
          Map<Object?, Object?>.from(item.value as Map),
        );
      }
      _entries
        ..clear()
        ..addAll(loaded);
      _prune();
    } catch (_) {
      _entries.clear();
    } finally {
      _loaded = true;
    }
  }

  bool _isExpired(OnlineLyricCacheEntry entry) =>
      DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs >
      ttl.inMilliseconds;

  void _prune() {
    _entries.removeWhere((_, entry) => _isExpired(entry));
    if (_entries.length <= maxEntries) return;
    final oldest = _entries.values.toList()
      ..sort((a, b) => a.fetchedAtMs.compareTo(b.fetchedAtMs));
    for (final entry in oldest.take(_entries.length - maxEntries)) {
      _entries.remove(entry.key);
    }
  }
}

Future<String?> readOnlineLyricCacheFromDirectory(Directory directory) async {
  final cacheFile = File(path.join(directory.path, 'online_lyric_cache.json'));
  final backupFile = File('${cacheFile.path}.bak');
  if (!await cacheFile.exists() && await backupFile.exists()) {
    await backupFile.rename(cacheFile.path);
  }
  await for (final entity in directory.list()) {
    final name = path.basename(entity.path);
    if (name == 'online_lyric_cache.json.bak' ||
        name.startsWith('online_lyric_cache.json.tmp')) {
      await entity.delete();
    }
  }
  return await cacheFile.exists() ? cacheFile.readAsString() : null;
}

int _atomicWriteSequence = 0;

Future<void> writeOnlineLyricCacheAtomically(
  Directory directory,
  String contents,
) async {
  final cacheFile = File(path.join(directory.path, 'online_lyric_cache.json'));
  final temporaryFile = File('${cacheFile.path}.tmp.${_atomicWriteSequence++}');
  final backupFile = File('${cacheFile.path}.bak');
  var movedCurrentToBackup = false;
  try {
    await temporaryFile.writeAsString(contents, flush: true);
    if (await cacheFile.exists()) {
      if (await backupFile.exists()) await backupFile.delete();
      await cacheFile.rename(backupFile.path);
      movedCurrentToBackup = true;
    }
    await temporaryFile.rename(cacheFile.path);
    if (movedCurrentToBackup) await backupFile.delete();
  } catch (_) {
    if (movedCurrentToBackup && await backupFile.exists()) {
      if (await cacheFile.exists()) await cacheFile.delete();
      await backupFile.rename(cacheFile.path);
    }
    rethrow;
  }
}
