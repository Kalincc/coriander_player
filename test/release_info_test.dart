import 'package:coriander_player/release_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the current fork tag with or without v prefix', () {
    expect(
      ForkReleaseVersion.parse('v1.5.1-kalin.1'),
      const ForkReleaseVersion(1, 5, 1, 1),
    );
    expect(
      ForkReleaseVersion.parse('1.5.1-kalin.1'),
      const ForkReleaseVersion(1, 5, 1, 1),
    );
  });

  test('orders upstream components before fork revision', () {
    expect(
      ForkReleaseVersion.parse('v1.5.1-kalin.2') >
          ForkReleaseVersion.parse('v1.5.1-kalin.1'),
      isTrue,
    );
    expect(
      ForkReleaseVersion.parse('v1.6.0-kalin.1') >
          ForkReleaseVersion.parse('v1.5.9-kalin.99'),
      isTrue,
    );
  });

  test('rejects tags outside the fork release scheme', () {
    expect(ForkReleaseVersion.tryParse('v1.5.1'), isNull);
    expect(ForkReleaseVersion.tryParse('latest'), isNull);
  });

  test('release constants point to the fork', () {
    expect(currentReleaseVersion, '1.5.1-kalin.9');
    expect(releaseRepositoryOwner, 'Kalincc');
    expect(releaseRepositoryName, 'coriander_player');
  });
}
