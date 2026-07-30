const currentReleaseVersion = '1.5.1-kalin.1';
const releaseRepositoryOwner = 'Kalincc';
const releaseRepositoryName = 'coriander_player';
const releaseRepositoryUrl =
    'https://github.com/$releaseRepositoryOwner/$releaseRepositoryName';

class ForkReleaseVersion implements Comparable<ForkReleaseVersion> {
  const ForkReleaseVersion(this.major, this.minor, this.patch, this.revision);

  final int major;
  final int minor;
  final int patch;
  final int revision;

  static final _pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)-kalin\.(\d+)$',
  );

  static ForkReleaseVersion parse(String value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid fork release: $value');
    }
    return parsed;
  }

  static ForkReleaseVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    return ForkReleaseVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
    );
  }

  @override
  int compareTo(ForkReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (revision, other.revision),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  bool operator >(ForkReleaseVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is ForkReleaseVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, revision);
}
