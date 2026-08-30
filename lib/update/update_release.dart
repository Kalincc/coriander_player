import 'package:coriander_player/release_info.dart';
import 'package:github/github.dart';

class UpdateCandidate {
  const UpdateCandidate({
    required this.version,
    required this.releaseName,
    required this.releaseNotes,
    required this.publishedAt,
    required this.releasePageUri,
    required this.installerFileName,
    required this.installerUri,
    required this.checksumUri,
  });

  final ForkReleaseVersion version;
  final String releaseName;
  final String releaseNotes;
  final DateTime? publishedAt;
  final Uri releasePageUri;
  final String installerFileName;
  final Uri installerUri;
  final Uri checksumUri;
}

class UpdateAssetException implements Exception {
  const UpdateAssetException(this.releasePageUri);

  final Uri releasePageUri;
}

UpdateCandidate? selectFormalUpdate(
  Iterable<Release> releases, {
  required ForkReleaseVersion current,
}) {
  Release? newestRelease;
  ForkReleaseVersion? newestVersion;

  for (final release in releases) {
    if (release.isDraft == true || release.isPrerelease == true) continue;

    final tag = release.tagName;
    final version = tag == null ? null : ForkReleaseVersion.tryParse(tag);
    if (version == null || version.compareTo(current) <= 0) continue;

    if (newestVersion == null || version > newestVersion) {
      newestRelease = release;
      newestVersion = version;
    }
  }

  final release = newestRelease;
  final version = newestVersion;
  if (release == null || version == null) return null;

  final versionText =
      '${version.major}.${version.minor}.${version.patch}-kalin.${version.revision}';
  final installerFileName = 'Coriander.Player.$versionText.Setup.exe';
  final assets = release.assets ?? const <ReleaseAsset>[];
  ReleaseAsset? installer;
  ReleaseAsset? checksum;
  for (final asset in assets) {
    if (asset.name == installerFileName) installer = asset;
    if (asset.name == 'SHA256SUMS.txt') checksum = asset;
  }

  final releasePageUri = _releasePageUri(release);
  final installerUri = _httpsAssetUri(installer?.browserDownloadUrl);
  final checksumUri = _httpsAssetUri(checksum?.browserDownloadUrl);
  if (installerUri == null || checksumUri == null) {
    throw UpdateAssetException(releasePageUri);
  }

  return UpdateCandidate(
    version: version,
    releaseName: release.name ?? 'Coriander Player $versionText',
    releaseNotes: release.body ?? '',
    publishedAt: release.publishedAt,
    releasePageUri: releasePageUri,
    installerFileName: installerFileName,
    installerUri: installerUri,
    checksumUri: checksumUri,
  );
}

Uri _releasePageUri(Release release) {
  final parsed = Uri.tryParse(release.htmlUrl ?? '');
  if (parsed != null && parsed.scheme == 'https' && parsed.host.isNotEmpty) {
    return parsed;
  }
  final tag = Uri.encodeComponent(release.tagName ?? '');
  return Uri.parse('$releaseRepositoryUrl/releases/tag/$tag');
}

Uri? _httpsAssetUri(String? value) {
  final parsed = value == null ? null : Uri.tryParse(value);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
    return null;
  }
  return parsed;
}
