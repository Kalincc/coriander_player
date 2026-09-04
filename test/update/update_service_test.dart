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
}
