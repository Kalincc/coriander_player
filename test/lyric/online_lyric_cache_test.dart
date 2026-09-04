import 'dart:convert';

import 'package:coriander_player/lyric/online_lyric_cache.dart';
import 'package:coriander_player/lyric/online_lyric_models.dart';
import 'package:flutter_test/flutter_test.dart';

OnlineLyricCacheEntry makeCacheEntry(
  String key, {
  required String fingerprint,
  int? fetchedAtMs,
}) =>
    OnlineLyricCacheEntry(
      key: key,
      audioFingerprint: fingerprint,
      payload: const OnlineLyricPayload(
        OnlineLyricFormat.lrc,
        '[00:01.00]primary',
        '[00:01.00]translation',
      ),
      title: 'Song',
      artists: 'Artist',
      album: 'Album',
      score: 0.9,
      fetchedAtMs: fetchedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );

void main() {
  test('round trips a payload and rejects a different audio fingerprint',
      () async {
    String? contents;
    final cache = OnlineLyricCache(
      read: () async => contents,
      write: (value) async => contents = value,
    );
    final entry = makeCacheEntry('qq:1', fingerprint: 'a');

    await cache.writeEntry(entry);

    expect(
      (await cache.readEntry('qq:1', audioFingerprint: 'a'))!.payload.lyricText,
      entry.payload.lyricText,
    );
    expect(
      (await cache.readEntry('qq:1', audioFingerprint: 'a'))!
          .payload
          .translationText,
      entry.payload.translationText,
    );
    expect(await cache.readEntry('qq:1', audioFingerprint: 'b'), isNull);
  });

  test('malformed JSON resets the cache without throwing', () async {
    final cache = OnlineLyricCache(
      read: () async => '{broken',
      write: (_) async {},
    );

    expect(await cache.readEntry('qq:1', audioFingerprint: 'a'), isNull);
  });

  test('keeps the 200 most recently fetched entries', () async {
    String? contents;
    final cache = OnlineLyricCache(
      read: () async => contents,
      write: (value) async => contents = value,
    );
    final firstFetchedAt = DateTime.now().millisecondsSinceEpoch - 205;
    for (var index = 0; index < 205; index++) {
      await cache.writeEntry(makeCacheEntry(
        'qq:$index',
        fingerprint: 'a',
        fetchedAtMs: firstFetchedAt + index,
      ));
    }

    final envelope = jsonDecode(contents!) as Map<String, dynamic>;
    final entries = envelope['entries'] as Map<String, dynamic>;
    expect(entries, hasLength(200));
    expect(entries, isNot(contains('qq:0')));
    expect(entries, contains('qq:204'));
  });

  test('rejects entries older than 30 days', () async {
    String? contents;
    final cache = OnlineLyricCache(
      read: () async => contents,
      write: (value) async => contents = value,
    );
    await cache.writeEntry(makeCacheEntry(
      'qq:1',
      fingerprint: 'a',
      fetchedAtMs: DateTime.now()
          .subtract(const Duration(days: 30, milliseconds: 1))
          .millisecondsSinceEpoch,
    ));

    expect(await cache.readEntry('qq:1', audioFingerprint: 'a'), isNull);
  });
}
