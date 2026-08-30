import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/update/update_release.dart';
import 'package:github/github.dart';

typedef ReleaseSource = Stream<Release> Function();

class UpdateService {
  UpdateService({required ReleaseSource releases}) : _releases = releases;

  final ReleaseSource _releases;

  factory UpdateService.github(GitHub github) {
    return UpdateService(
      releases: () => github.repositories.listReleases(
        RepositorySlug(releaseRepositoryOwner, releaseRepositoryName),
      ),
    );
  }

  Future<UpdateCandidate?> check(ForkReleaseVersion current) async {
    return selectFormalUpdate(
      await _releases().toList(),
      current: current,
    );
  }
}
