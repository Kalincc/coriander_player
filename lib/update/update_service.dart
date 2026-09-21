import 'dart:async';
import 'dart:io';

import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/update/update_release.dart';
import 'package:github/github.dart';

typedef ReleaseSource = Stream<Release> Function();

const defaultUpdateCheckTimeout = Duration(seconds: 15);

class UpdateService {
  UpdateService({
    required ReleaseSource releases,
    Duration timeout = defaultUpdateCheckTimeout,
  })  : _releases = releases,
        _timeout = timeout;

  final ReleaseSource _releases;
  final Duration _timeout;

  factory UpdateService.github(
    GitHub github, {
    Duration timeout = defaultUpdateCheckTimeout,
  }) {
    return UpdateService(
      releases: () => Stream.fromFuture(
        _latestRelease(github, timeout: timeout),
      ),
      timeout: timeout,
    );
  }

  Future<UpdateCandidate?> check(ForkReleaseVersion current) async {
    return selectFormalUpdate(
      await _releases().toList().timeout(_timeout),
      current: current,
    );
  }
}

Future<Release> _latestRelease(
  GitHub github, {
  required Duration timeout,
}) async {
  final apiTimeout = timeout < const Duration(seconds: 5)
      ? timeout
      : const Duration(seconds: 5);
  try {
    return await github.repositories
        .getLatestRelease(
          RepositorySlug(releaseRepositoryOwner, releaseRepositoryName),
        )
        .timeout(apiTimeout);
  } catch (_) {
    return _latestReleaseFromWeb(timeout: timeout);
  }
}

Future<Release> _latestReleaseFromWeb({required Duration timeout}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  var currentUri = Uri.parse('$releaseRepositoryUrl/releases/latest');
  try {
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final request = await client.getUrl(currentUri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'CorianderPlayer');
      final response = await request.close().timeout(timeout);
      final isRedirect =
          response.statusCode >= 300 && response.statusCode < 400;
      if (!isRedirect) {
        await response.drain<void>();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError(
            'GitHub 最新发布页返回 HTTP ${response.statusCode}。',
          );
        }
        return _releaseFromTagUri(currentUri);
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || location.isEmpty) {
        throw StateError('GitHub 最新发布页缺少重定向地址。');
      }
      final nextUri = currentUri.resolve(location);
      if (nextUri.scheme != 'https' || nextUri.host != 'github.com') {
        throw StateError('GitHub 最新发布页重定向到了不安全地址。');
      }
      currentUri = nextUri;
    }
    throw StateError('GitHub 最新发布页重定向次数过多。');
  } finally {
    client.close(force: true);
  }
}

Release _releaseFromTagUri(Uri uri) {
  final segments = uri.pathSegments;
  final tagIndex = segments.indexOf('tag');
  if (tagIndex < 0 || tagIndex + 1 >= segments.length) {
    throw StateError('GitHub 最新发布页地址中缺少版本标签。');
  }
  final tag = Uri.decodeComponent(segments[tagIndex + 1]);
  final version = ForkReleaseVersion.tryParse(tag);
  if (version == null) {
    throw StateError('GitHub 最新发布页包含无法识别的版本标签。');
  }

  final versionText =
      '${version.major}.${version.minor}.${version.patch}-kalin.${version.revision}';
  final installerName = 'Coriander.Player.$versionText.Setup.exe';
  final downloadBase =
      '$releaseRepositoryUrl/releases/download/${Uri.encodeComponent(tag)}';
  return Release(
    tagName: tag,
    name: 'Coriander Player $versionText',
    body: '',
    htmlUrl: uri.toString(),
    isDraft: false,
    isPrerelease: false,
    assets: [
      ReleaseAsset(
        name: installerName,
        browserDownloadUrl: '$downloadBase/$installerName',
      ),
      ReleaseAsset(
        name: 'SHA256SUMS.txt',
        browserDownloadUrl: '$downloadBase/SHA256SUMS.txt',
      ),
    ],
  );
}
