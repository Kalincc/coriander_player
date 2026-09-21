import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/update/update_release.dart';
import 'package:coriander_player/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github/github.dart';

Release release(
  String tag, {
  bool isDraft = false,
  bool isPrerelease = false,
  String? setupName,
  String setupScheme = 'https',
  bool includeChecksum = true,
}) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  final setup = setupName ?? 'Coriander.Player.$version.Setup.exe';
  final assets = <ReleaseAsset>[
    ReleaseAsset(
      name: setup,
      browserDownloadUrl: '$setupScheme://example.com/$setup',
    ),
  ];
  if (includeChecksum) {
    assets.add(
      ReleaseAsset(
        name: 'SHA256SUMS.txt',
        browserDownloadUrl: 'https://example.com/SHA256SUMS.txt',
      ),
    );
  }
  return Release(
    tagName: tag,
    name: 'Coriander Player $version',
    body: 'notes for $version',
    htmlUrl: 'https://github.com/Kalincc/coriander_player/releases/tag/$tag',
    isDraft: isDraft,
    isPrerelease: isPrerelease,
    assets: assets,
  );
}

void main() {
  test('selects the newest formal release with exact assets', () {
    final candidate = selectFormalUpdate(
      [
        release('v1.5.1-kalin.11'),
        release('v1.5.1-kalin.10'),
      ],
      current: ForkReleaseVersion.parse('1.5.1-kalin.9'),
    );

    expect(candidate?.version, ForkReleaseVersion.parse('1.5.1-kalin.11'));
    expect(
      candidate?.installerFileName,
      'Coriander.Player.1.5.1-kalin.11.Setup.exe',
    );
    expect(candidate?.installerUri.scheme, 'https');
    expect(candidate?.checksumUri.path, '/SHA256SUMS.txt');
  });

  test('rejects drafts, prereleases, and approximate assets', () {
    expect(
      () => selectFormalUpdate(
        [
          release('v1.5.1-kalin.12', isDraft: true),
          release('v1.5.1-kalin.11', isPrerelease: true),
          release('v1.5.1-kalin.10', setupName: 'similar.Setup.exe'),
        ],
        current: ForkReleaseVersion.parse('1.5.1-kalin.9'),
      ),
      throwsA(isA<UpdateAssetException>()),
    );
  });

  test('rejects missing checksums and non-HTTPS setup assets', () {
    expect(
      () => selectFormalUpdate(
        [release('v1.5.1-kalin.10', includeChecksum: false)],
        current: ForkReleaseVersion.parse('1.5.1-kalin.9'),
      ),
      throwsA(isA<UpdateAssetException>()),
    );
    expect(
      () => selectFormalUpdate(
        [release('v1.5.1-kalin.10', setupScheme: 'http')],
        current: ForkReleaseVersion.parse('1.5.1-kalin.9'),
      ),
      throwsA(isA<UpdateAssetException>()),
    );
  });

  test('returns no update when all formal versions are current or older', () {
    expect(
      selectFormalUpdate(
        [release('v1.5.1-kalin.9'), release('v1.5.1-kalin.8')],
        current: ForkReleaseVersion.parse(currentReleaseVersion),
      ),
      isNull,
    );
  });

  test('service gathers the complete release stream before selecting',
      () async {
    final service = UpdateService(
      releases: () => Stream.fromIterable([
        release('v1.5.1-kalin.11'),
      ]),
    );

    final candidate = await service.check(
      // Keep this stream-collection test independent of the app's release
      // bump; version-specific update fixtures are covered above.
      ForkReleaseVersion.parse('1.5.1-kalin.10'),
    );

    expect(candidate?.version, ForkReleaseVersion.parse('1.5.1-kalin.11'));
  });

  test('github source requests the latest release endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? requestPath;
    server.listen((request) async {
      requestPath = request.uri.path;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'tag_name': 'v1.5.1-kalin.14',
          'name': 'Coriander Player 1.5.1-kalin.14',
          'body': 'notes',
          'html_url':
              'https://github.com/Kalincc/coriander_player/releases/tag/v1.5.1-kalin.14',
          'draft': false,
          'prerelease': false,
          'assets': [
            {
              'name': 'Coriander.Player.1.5.1-kalin.14.Setup.exe',
              'browser_download_url':
                  'https://example.com/Coriander.Player.1.5.1-kalin.14.Setup.exe',
            },
            {
              'name': 'SHA256SUMS.txt',
              'browser_download_url': 'https://example.com/SHA256SUMS.txt',
            },
          ],
        }));
      await request.response.close();
    });

    final service = UpdateService.github(
      GitHub(endpoint: 'http://127.0.0.1:${server.port}'),
    );
    final candidate = await service.check(
      ForkReleaseVersion.parse('1.5.1-kalin.13'),
    );

    expect(requestPath, '/repos/Kalincc/coriander_player/releases/latest');
    expect(candidate?.version, ForkReleaseVersion.parse('1.5.1-kalin.14'));
  });

  test('times out a stalled release source', () async {
    final pending = Completer<Release>();
    final service = UpdateService(
      releases: () => Stream.fromFuture(pending.future),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      service.check(ForkReleaseVersion.parse('1.5.1-kalin.13')),
      throwsA(isA<TimeoutException>()),
    );
  });
}
