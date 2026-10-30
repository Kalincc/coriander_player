import 'dart:async';

import 'package:coriander_player/library/artwork_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ImageProvider?> request(ArtworkCache cache, String path,
        {int width = 48, int modified = 1}) =>
    cache.get(
        path: path,
        modified: modified,
        created: 1,
        width: width,
        height: width);

void main() {
  test(
      'distinct covers have bounded decoding and pending reads stay deduplicated',
      () async {
    final gates = <Completer<ImageProvider?>>[];
    final cache = ArtworkCache(
      capacity: 1,
      maxConcurrentLoads: 2,
      load: (_, __, ___) {
        final gate = Completer<ImageProvider?>();
        gates.add(gate);
        return gate.future;
      },
    );
    final pending = [for (var i = 0; i < 6; i++) request(cache, '$i.flac')];
    expect(gates, hasLength(2));
    expect(request(cache, '0.flac'), same(pending.first));
    for (var i = 0; i < 6; i++) {
      gates[i].complete(null);
      await pending[i];
      expect(gates.length, lessThanOrEqualTo(i + 3));
    }
    expect(await Future.wait(pending), everyElement(isNull));
  });

  test('LRU evicts old entries rather than retaining covers for every song',
      () async {
    var reads = 0;
    final cache = ArtworkCache(
        capacity: 2,
        load: (_, __, ___) async {
          reads++;
          return null;
        });
    final first = request(cache, r'D:\Music\one.flac');
    await request(cache, 'D:/Music/two.flac');
    expect(request(cache, 'd:/music/one.flac'), same(first));
    await request(cache, 'D:/Music/three.flac');
    await request(cache, 'D:/Music/two.flac');
    expect(reads, 4);
  });

  test('physical size and file timestamp use distinct entries', () async {
    var reads = 0;
    final cache = ArtworkCache(load: (_, __, ___) async {
      reads++;
      return null;
    });
    await request(cache, 'same.flac');
    await request(cache, 'same.flac', width: 200);
    await request(cache, 'same.flac', modified: 2);
    await request(cache, 'same.flac');
    expect(reads, 3);
  });

  test('failed reads can retry while missing covers remain cached', () async {
    var reads = 0;
    final cache = ArtworkCache(load: (_, __, ___) {
      reads++;
      if (reads == 1) throw StateError('unreadable file');
      return Future.value(null);
    });
    await expectLater(request(cache, 'retry.flac'), throwsStateError);
    expect(await request(cache, 'retry.flac'), isNull);
    expect(await request(cache, 'retry.flac'), isNull);
    expect(reads, 2);
  });

  test('a failed decoder releases its slot to a queued request', () async {
    final blocked = Completer<ImageProvider?>();
    var reads = 0;
    final cache = ArtworkCache(
      maxConcurrentLoads: 1,
      load: (_, __, ___) => ++reads == 1 ? blocked.future : Future.value(null),
    );
    final first = request(cache, 'bad.flac');
    final failed = expectLater(first, throwsStateError);
    final second = request(cache, 'good.flac');
    expect(reads, 1);
    blocked.completeError(StateError('decode failed'));
    await failed;
    expect(await second, isNull);
    expect(reads, 2);
  });

  test('clearing pending entries cannot let stale failures remove new reads',
      () async {
    final old = Completer<ImageProvider?>();
    final fresh = Completer<ImageProvider?>();
    var reads = 0;
    final cache = ArtworkCache(
        load: (_, __, ___) => ++reads == 1 ? old.future : fresh.future);
    final stale = request(cache, 'rescan.flac');
    final failure = expectLater(stale, throwsStateError);
    cache.clear();
    final current = request(cache, 'rescan.flac');
    old.completeError(StateError('old request failed'));
    await failure;
    expect(request(cache, 'rescan.flac'), same(current));
    fresh.complete(null);
    expect(await current, isNull);
    expect(reads, 2);
  });
}
