import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/page/settings_page/check_update.dart';
import 'package:coriander_player/update/update_controller.dart';
import 'package:coriander_player/update/update_downloader.dart';
import 'package:coriander_player/update/update_release.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('installed edition offers one-click update', (tester) async {
    final controller = FakeUpdateController(
      UpdateAvailable(candidate, canAutoInstall: true),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CheckForUpdate(controller: controller)),
    ));

    expect(find.byKey(const Key('install-update-button')), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    await tester.tap(find.byKey(const Key('install-update-button')));
    expect(controller.installCalls, 1);
  });

  testWidgets('portable edition only opens the release page', (tester) async {
    final controller = FakeUpdateController(
      UpdateAvailable(candidate, canAutoInstall: false),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CheckForUpdate(controller: controller)),
    ));

    expect(find.text('下载新版本'), findsOneWidget);
    expect(find.textContaining('Portable'), findsOneWidget);
    expect(find.byKey(const Key('install-update-button')), findsNothing);
  });

  testWidgets('download progress exposes cancellation only while downloading',
      (tester) async {
    final controller = FakeUpdateController(
      UpdateDownloading(
        candidate,
        const UpdateDownloadProgress(
          phase: UpdateDownloadPhase.downloading,
          receivedBytes: 50,
          totalBytes: 100,
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CheckForUpdate(controller: controller)),
    ));

    expect(find.byKey(const Key('update-download-progress')), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-update-download-button')));
    expect(controller.cancelCalls, 1);

    controller.setState(UpdateVerifying(candidate));
    await tester.pump();
    expect(find.byKey(const Key('cancel-update-download-button')), findsNothing);
  });

  testWidgets('retry is shown for recoverable failures', (tester) async {
    final controller = FakeUpdateController(
      const UpdateFailed('下载更新失败，请检查网络后重试。', canRetry: true),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CheckForUpdate(controller: controller)),
    ));

    expect(find.byKey(const Key('retry-update-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-update-button')));
    expect(controller.checkCalls, 1);
  });
}

final candidate = UpdateCandidate(
  version: ForkReleaseVersion.parse('1.5.1-kalin.10'),
  releaseName: 'Coriander Player 1.5.1-kalin.10',
  releaseNotes: '更新说明',
  publishedAt: null,
  releasePageUri: Uri.parse(
    'https://github.com/Kalincc/coriander_player/releases/tag/v1.5.1-kalin.10',
  ),
  installerFileName: 'Coriander.Player.1.5.1-kalin.10.Setup.exe',
  installerUri: Uri.parse('https://example.com/installer.exe'),
  checksumUri: Uri.parse('https://example.com/SHA256SUMS.txt'),
);

class FakeUpdateController extends ChangeNotifier
    implements UpdateControllerView {
  FakeUpdateController(this._state);

  UpdateState _state;
  int checkCalls = 0;
  int installCalls = 0;
  int cancelCalls = 0;

  @override
  UpdateState get state => _state;

  @override
  Future<void> check() async {
    checkCalls++;
  }

  @override
  Future<void> install() async {
    installCalls++;
  }

  @override
  void cancelDownload() {
    cancelCalls++;
  }

  void setState(UpdateState state) {
    _state = state;
    notifyListeners();
  }
}
