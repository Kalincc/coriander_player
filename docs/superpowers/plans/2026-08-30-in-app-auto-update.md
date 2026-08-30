# In-App Automatic Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 让安装版用户确认一次后，安全下载最新正式版、原位置静默覆盖安装并自动重启播放器。

**Architecture:** 将 Release 选择、安装版识别、下载校验、安装器启动、应用退出、状态协调和界面分成独立单元；网络、文件、注册表、进程与退出操作都可注入测试。Inno Setup 继续使用固定 AppId，通过注册记录沿用原安装目录。

**Tech Stack:** Flutter 3.38.9、Dart 3.10.8、github 9.24.0、crypto 3.0.x、win32 5.11.0、ffi 2.1.0、Inno Setup 6、PowerShell、Flutter Test。

## Global Constraints

- 目标版本是 v1.5.1-kalin.10；未经用户另行授权，不得推送、打标签或发布 Release。
- .9 → .10 需要最后一次手动覆盖安装，但不需要卸载 .9。
- 只有固定 Inno Setup AppId 的注册目录与当前 EXE 目录一致时才允许自动安装。
- 只接受 Kalincc/coriander_player 的非草稿、非预发布正式 Release。
- 只接受精确命名的 Coriander.Player.<version>.Setup.exe 与 SHA256SUMS.txt。
- 所有资产 URL 必须为 HTTPS；Setup 必须通过 SHA-256 才能执行。
- 不读取、迁移或删除 Documents\coriander_player 中的用户数据。
- 安装器继续使用 PrivilegesRequired=lowest。
- Portable 版不得自动安装出第二份软件。
- 不实现启动自动检查、后台下载、强制更新、多通道、断点续传、差分更新或独立 updater。
- 保存、校验或安装器启动失败时，当前播放器必须继续运行。
- 每项生产行为遵循 TDD，每个任务独立提交。

---

## File Structure

新增生产文件：

- lib/update/update_release.dart：候选版本模型与纯 Release 筛选。
- lib/update/update_service.dart：固定 GitHub 仓库的 API 适配器。
- lib/update/install_environment.dart：安装版/Portable 识别。
- lib/src/windows/install_registry.dart：集中封装 Win32 注册表 FFI。
- lib/update/update_downloader.dart：流式下载、取消和 SHA-256 校验。
- lib/update/update_installer.dart：静默安装参数与独立进程启动。
- lib/application_shutdown.dart：正常退出和更新退出共用流程。
- lib/update/update_controller.dart：更新状态机与流程协调。

新增测试：

- test/update/update_service_test.dart
- test/update/install_environment_test.dart
- test/update/update_downloader_test.dart
- test/update/update_installer_test.dart
- test/application_shutdown_test.dart
- test/update/update_controller_test.dart
- test/page/check_update_test.dart
- scripts/tests/installer_contract_test.ps1

---

### Task 1: Formal Release Discovery

**Files:**
- Create: lib/update/update_release.dart
- Create: lib/update/update_service.dart
- Create: test/update/update_service_test.dart
- Modify: pubspec.yaml
- Modify: pubspec.lock

**Interfaces:**
- Consumes: ForkReleaseVersion、Release、ReleaseAsset、GitHub。
- Produces: UpdateCandidate、selectFormalUpdate(...)、UpdateService.check(...)。

- [ ] **Step 1: 声明直接依赖**

在 pubspec.yaml 设置：

~~~yaml
dependencies:
  crypto: ^3.0.6
  win32: ^5.11.0
~~~

保留现有 Dart SDK 声明。运行 flutter pub get。Expected: 当前锁文件中的 crypto 与 win32 从间接依赖变成直接依赖，不引入新的运行时包。

- [ ] **Step 2: 先写 Release 筛选失败测试**

~~~dart
test('selects the newest formal release with exact assets', () {
  final candidate = selectFormalUpdate(
    [release('v1.5.1-kalin.11'), release('v1.5.1-kalin.10')],
    current: ForkReleaseVersion.parse('1.5.1-kalin.9'),
  );

  expect(candidate?.version, ForkReleaseVersion.parse('1.5.1-kalin.11'));
  expect(
    candidate?.installerFileName,
    'Coriander.Player.1.5.1-kalin.11.Setup.exe',
  );
  expect(candidate?.installerUri.scheme, 'https');
});

test('rejects drafts prereleases and approximate assets', () {
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
~~~

另测错误标签、缺失 SHA256SUMS.txt、非 HTTPS URL 和不高于当前版本。

- [ ] **Step 3: 运行测试确认红灯**

Run: flutter test --no-pub test/update/update_service_test.dart

Expected: FAIL，因为候选模型和选择函数不存在。

- [ ] **Step 4: 实现候选模型与纯选择函数**

~~~dart
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

UpdateCandidate? selectFormalUpdate(
  Iterable<Release> releases, {
  required ForkReleaseVersion current,
});

class UpdateAssetException implements Exception {
  const UpdateAssetException(this.releasePageUri);
  final Uri releasePageUri;
}
~~~

遍历全部 Release，不依赖 API 顺序；先找出大于当前版本的最大正式版本，再验证它的资产。去掉一个前导 v 后生成精确 Setup 文件名；必须同时找到 Setup 和 SHA256SUMS.txt。最高版本资产缺失、近似或非 HTTPS 时抛出携带 Release 页面地址的 UpdateAssetException，不得退回旧版本。

- [ ] **Step 5: 实现可注入 GitHub 适配器**

~~~dart
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
~~~

- [ ] **Step 6: 验证并提交**

Run:

~~~powershell
flutter test --no-pub test/update/update_service_test.dart test/release_info_test.dart
git add -- pubspec.yaml pubspec.lock lib/update/update_release.dart lib/update/update_service.dart test/update/update_service_test.dart
git commit -m "feat: discover installable player updates"
~~~

Expected: 测试 PASS，提交只包含本任务文件。

---

### Task 2: Installed Edition Detection

**Files:**
- Create: lib/update/install_environment.dart
- Create: lib/src/windows/install_registry.dart
- Create: test/update/install_environment_test.dart

**Interfaces:**
- Consumes: 当前 EXE 路径和 Inno 当前用户卸载记录。
- Produces: InstallEnvironment.isInstalledEdition()。

- [ ] **Step 1: 写失败测试**

~~~dart
test('accepts matching registered and executable directories', () {
  final environment = InstallEnvironment(
    readInstallLocation: () => 'C:\\Apps\\Coriander Player\\',
    executablePath: () => r'c:\apps\coriander player\coriander_player.exe',
    isWindows: () => true,
  );

  expect(environment.isInstalledEdition(), isTrue);
});

test('treats a different executable directory as portable', () {
  final environment = InstallEnvironment(
    readInstallLocation: () => r'C:\Apps\Coriander Player',
    executablePath: () => r'D:\Portable\coriander_player.exe',
    isWindows: () => true,
  );

  expect(environment.isInstalledEdition(), isFalse);
});
~~~

另测注册缺失、注册读取异常和非 Windows 均返回 false。

- [ ] **Step 2: 运行测试确认红灯**

Run: flutter test --no-pub test/update/install_environment_test.dart

Expected: FAIL，因为 InstallEnvironment 不存在。

- [ ] **Step 3: 实现路径比较与注册表读取**

~~~dart
const installerAppId = '{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}';
const installerRegistryPath =
    r'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}_is1';

class InstallEnvironment {
  InstallEnvironment({
    required String? Function() readInstallLocation,
    required String Function() executablePath,
    required bool Function() isWindows,
  });

  factory InstallEnvironment.windows();

  bool isInstalledEdition();
}
~~~

使用 path.windows.normalize、移除尾部分隔符并忽略大小写；将注册目录与 path.windows.dirname(executablePath) 比较。

生产读取器集中放入 lib/src/windows/install_registry.dart，使用现有 ffi 与 win32 依赖调用 RegGetValue 两次：第一次取得 UTF-16 缓冲区大小，第二次读取 InstallLocation。所有 calloc 指针都在 finally 中释放，任何非 ERROR_SUCCESS 结果返回 null。核心结构如下：

~~~dart
String? readInnoInstallLocation(String subKeyPath) {
  final subKey = subKeyPath.toNativeUtf16();
  final valueName = 'InstallLocation'.toNativeUtf16();
  final byteCount = calloc<Uint32>();
  try {
    final sizeResult = RegGetValue(
      HKEY_CURRENT_USER,
      subKey,
      valueName,
      RRF_RT_REG_SZ,
      nullptr,
      nullptr,
      byteCount,
    );
    if (sizeResult != ERROR_SUCCESS || byteCount.value == 0) return null;

    final buffer = calloc<Uint8>(byteCount.value);
    try {
      final readResult = RegGetValue(
        HKEY_CURRENT_USER,
        subKey,
        valueName,
        RRF_RT_REG_SZ,
        nullptr,
        buffer,
        byteCount,
      );
      if (readResult != ERROR_SUCCESS) return null;
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(byteCount);
    calloc.free(valueName);
    calloc.free(subKey);
  }
}
~~~

InstallEnvironment.windows() 仅在 Platform.isWindows 时调用该原生边界。

- [ ] **Step 4: 验证并提交**

~~~powershell
flutter test --no-pub test/update/install_environment_test.dart
git add -- lib/update/install_environment.dart lib/src/windows/install_registry.dart test/update/install_environment_test.dart
git commit -m "feat: detect installed player editions"
~~~

Expected: 大小写、尾斜杠、缺失和不匹配场景均 PASS。

---

### Task 3: Streaming Download and SHA-256 Verification

**Files:**
- Create: lib/update/update_downloader.dart
- Create: test/update/update_downloader_test.dart

**Interfaces:**
- Consumes: UpdateCandidate 和临时目录。
- Produces: UpdateDownloader.downloadAndVerify(...)、UpdateCancellation、UpdateDownloadProgress、VerifiedUpdate。

- [ ] **Step 1: 写失败的清单和下载测试**

~~~dart
test('selects the exact installer hash', () {
  const manifest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.exe\n'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  Coriander.Player.1.5.1-kalin.10.Setup.exe\n';

  expect(
    expectedSha256(
      manifest,
      'Coriander.Player.1.5.1-kalin.10.Setup.exe',
    ),
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );
});
~~~

使用本机 HttpServer 测试成功下载、进度、非 200、断网、取消、哈希不匹配和 .part 清理。

- [ ] **Step 2: 运行测试确认红灯**

Run: flutter test --no-pub test/update/update_downloader_test.dart

Expected: FAIL，因为下载接口不存在。

- [ ] **Step 3: 实现公共类型**

~~~dart
enum UpdateDownloadPhase { downloading, verifying }

class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final UpdateDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : receivedBytes / totalBytes!;
}

class UpdateCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
}

class VerifiedUpdate {
  const VerifiedUpdate({required this.installer, required this.installLog});
  final File installer;
  final File installLog;
}
~~~

- [ ] **Step 4: 实现下载与校验**

~~~dart
class UpdateDownloader {
  UpdateDownloader({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<VerifiedUpdate> downloadAndVerify(
    UpdateCandidate candidate,
    Directory temporaryDirectory, {
    required UpdateCancellation cancellation,
    required void Function(UpdateDownloadProgress progress) onProgress,
  });
}
~~~

先取清单，再将 Setup 流式写入 <filename>.part。每个 chunk 检查取消；所有失败路径关闭 sink 并删除 .part。完整下载后改名并流式计算：

~~~dart
Future<String> fileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString().toLowerCase();
}
~~~

哈希不匹配时删除正式文件。日志路径为同一临时目录中的 Coriander.Player.<version>.Install.log。

- [ ] **Step 5: 验证并提交**

~~~powershell
flutter test --no-pub test/update/update_downloader_test.dart
git add -- lib/update/update_downloader.dart test/update/update_downloader_test.dart
git commit -m "feat: securely download player updates"
~~~

Expected: PASS，tearDown 后没有残留服务器和临时目录。

---

### Task 4: Installer Handoff

**Files:**
- Create: lib/update/update_installer.dart
- Create: test/update/update_installer_test.dart
- Create: scripts/tests/installer_contract_test.ps1
- Modify: installer/coriander_player.iss
- Modify: .github/workflows/release.yml

**Interfaces:**
- Consumes: VerifiedUpdate。
- Produces: UpdateInstaller.start(...) 和 /CORIANDERAPPUPDATE=1 契约。

- [ ] **Step 1: 写失败的启动参数测试**

~~~dart
test('launches the installer with silent update arguments', () async {
  String? executable;
  List<String>? arguments;
  final updater = UpdateInstaller(
    startDetached: (path, args) async {
      executable = path;
      arguments = args;
    },
  );

  await updater.start(
    installer: File(r'C:\Temp\Coriander.Setup.exe'),
    log: File(r'C:\Temp\Coriander.Install.log'),
  );

  expect(executable, r'C:\Temp\Coriander.Setup.exe');
  expect(arguments, containsAll([
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    '/CORIANDERAPPUPDATE=1',
    r'/LOG="C:\Temp\Coriander.Install.log"',
  ]));
});
~~~

另测 starter 抛错必须向上传递。

- [ ] **Step 2: 运行测试确认红灯**

Run: flutter test --no-pub test/update/update_installer_test.dart

Expected: FAIL，因为 UpdateInstaller 不存在。

- [ ] **Step 3: 实现独立进程启动器**

~~~dart
typedef DetachedProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);

Future<void> startDetachedProcess(
  String executable,
  List<String> arguments,
) async {
  await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detached,
  );
}

class UpdateInstaller {
  UpdateInstaller({DetachedProcessStarter? startDetached})
      : _startDetached = startDetached ?? startDetachedProcess;

  final DetachedProcessStarter _startDetached;

  Future<void> start({required File installer, required File log});
}
~~~

不得传 /DIR，必须让固定 AppId 沿用注册目录。

- [ ] **Step 4: 写 PowerShell 契约测试并先观察失败**

~~~powershell
$requiredPatterns = @(
    'AppId={{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}',
    'PrivilegesRequired=lowest',
    'CORIANDERAPPUPDATE',
    'Check: IsAppUpdate'
)
~~~

脚本还要断言普通 [Run] 条目保留 skipifsilent。

Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/installer_contract_test.ps1

Expected: FAIL，因为专用参数尚不存在。

- [ ] **Step 5: 增加成功后重启规则**

~~~ini
[Run]
Filename: "{app}\coriander_player.exe"; Description: "启动 Coriander Player"; Flags: nowait postinstall skipifsilent
Filename: "{app}\coriander_player.exe"; Flags: nowait; Check: IsAppUpdate

[Code]
function IsAppUpdate: Boolean;
begin
  Result := ExpandConstant('{param:CORIANDERAPPUPDATE|0}') = '1';
end;
~~~

在 workflow 的 release helper 测试后加入 installer contract 测试步骤。Inno 只有安装成功才执行 [Run]。

- [ ] **Step 6: 验证并提交**

~~~powershell
flutter test --no-pub test/update/update_installer_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/installer_contract_test.ps1
git add -- lib/update/update_installer.dart test/update/update_installer_test.dart installer/coriander_player.iss scripts/tests/installer_contract_test.ps1 .github/workflows/release.yml
git commit -m "feat: hand updates to the silent installer"
~~~

Expected: Dart 和 PowerShell 测试均 PASS。

---

### Task 5: Shared Safe Shutdown

**Files:**
- Create: lib/application_shutdown.dart
- Create: test/application_shutdown_test.dart
- Modify: lib/component/title_bar.dart

**Interfaces:**
- Consumes: 现有保存、播放、桌面歌词、快捷键和窗口 API。
- Produces: saveUserState()、closeAfterUpdateHandoff()、exitNormally()。

- [ ] **Step 1: 写失败的顺序测试**

~~~dart
test('saves before closing resources', () async {
  final events = <String>[];
  final shutdown = shutdownFixture(events);

  await shutdown.exitNormally();

  expect(events, [
    'playlists',
    'lyrics',
    'settings',
    'preferences',
    'playback',
    'hotkeys',
    'window',
  ]);
});
~~~

另测任一保存失败时不得出现 playback 或 window。

- [ ] **Step 2: 运行测试确认红灯**

Run: flutter test --no-pub test/application_shutdown_test.dart

Expected: FAIL，因为统一退出服务不存在。

- [ ] **Step 3: 实现分阶段退出**

~~~dart
class ApplicationShutdown {
  ApplicationShutdown({
    required Future<void> Function() savePlaylists,
    required Future<void> Function() saveLyricSources,
    required Future<void> Function() saveSettings,
    required Future<void> Function() savePreferences,
    required void Function() closePlayback,
    required Future<void> Function() unregisterHotkeys,
    required Future<void> Function() closeWindow,
  });

  factory ApplicationShutdown.production();

  Future<void> saveUserState();
  Future<void> closeAfterUpdateHandoff();

  Future<void> exitNormally() async {
    await saveUserState();
    await closeAfterUpdateHandoff();
  }
}
~~~

saveUserState 依次等待四项保存；closeAfterUpdateHandoff 调用 PlayService.instance.close()，再等待快捷键注销和窗口关闭。更新流程因此可以先保存、再启动安装器，启动成功后才释放播放资源。

- [ ] **Step 4: 标题栏复用统一退出**

~~~dart
onPressed: () async {
  try {
    await ApplicationShutdown.production().exitNormally();
  } catch (error, stackTrace) {
    LOGGER.e(error, stackTrace: stackTrace);
    showTextOnSnackBar('保存数据失败，播放器未退出。');
  }
},
~~~

- [ ] **Step 5: 验证并提交**

~~~powershell
flutter test --no-pub test/application_shutdown_test.dart test/play_service/playback_history_service_test.dart
git add -- lib/application_shutdown.dart lib/component/title_bar.dart test/application_shutdown_test.dart
git commit -m "refactor: centralize safe application shutdown"
~~~

Expected: PASS，标题栏其他按钮行为不变。

---

### Task 6: Update State Machine

**Files:**
- Create: lib/update/update_controller.dart
- Create: test/update/update_controller_test.dart

**Interfaces:**
- Consumes: Tasks 1–5 和临时目录工厂。
- Produces: UpdateControllerView、UpdateController 与 Task 7 使用的状态类。

- [ ] **Step 1: 写失败的流程测试**

~~~dart
test('installed update saves launches then closes in order', () async {
  final events = <String>[];
  final controller = controllerFixture(installed: true, events: events);

  await controller.check();
  await controller.install();

  expect(events, [
    'check',
    'download',
    'verify',
    'save',
    'launch',
    'close',
  ]);
});

test('installer launch failure leaves player open', () async {
  final events = <String>[];
  final controller = controllerFixture(
    installed: true,
    events: events,
    launchError: StateError('cannot start'),
  );

  await controller.check();
  await controller.install();

  expect(controller.state, isA<UpdateFailed>());
  expect(events, isNot(contains('close')));
});
~~~

另测无更新、Portable、取消、哈希失败、保存失败、重复点击、dispose 后回调和旧 generation 覆盖。

- [ ] **Step 2: 运行测试确认红灯**

Run: flutter test --no-pub test/update/update_controller_test.dart

Expected: FAIL，因为状态机不存在。

- [ ] **Step 3: 实现固定状态契约**

~~~dart
sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState { const UpdateIdle(); }
class UpdateChecking extends UpdateState { const UpdateChecking(); }
class UpdateCurrent extends UpdateState { const UpdateCurrent(); }

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.candidate, {required this.canAutoInstall});
  final UpdateCandidate candidate;
  final bool canAutoInstall;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.candidate, this.progress);
  final UpdateCandidate candidate;
  final UpdateDownloadProgress progress;
}

class UpdateVerifying extends UpdateState {
  const UpdateVerifying(this.candidate);
  final UpdateCandidate candidate;
}

class UpdatePreparingInstall extends UpdateState {
  const UpdatePreparingInstall(this.candidate);
  final UpdateCandidate candidate;
}

class UpdateCancelled extends UpdateState { const UpdateCancelled(); }

class UpdateFailed extends UpdateState {
  const UpdateFailed(
    this.message, {
    required this.canRetry,
    this.releasePageUri,
  });
  final String message;
  final bool canRetry;
  final Uri? releasePageUri;
}
~~~

- [ ] **Step 4: 实现协调器**

~~~dart
abstract interface class UpdateControllerView implements Listenable {
  UpdateState get state;
  Future<void> check();
  Future<void> install();
  void cancelDownload();
}

class UpdateController extends ChangeNotifier
    implements UpdateControllerView {
  UpdateController({
    required UpdateService service,
    required InstallEnvironment environment,
    required UpdateDownloader downloader,
    required UpdateInstaller installer,
    required ApplicationShutdown shutdown,
    required Future<Directory> Function() createTemporaryDirectory,
  });

  factory UpdateController.production();

}
~~~

使用递增 generation、_busy 和 disposed 标记。顺序固定为：检查 → 下载 → 校验 → 保存 → 启动安装器 → 关闭应用。Portable 设置 canAutoInstall: false，且不得创建下载目录。UpdateAssetException 转为不可重试的 UpdateFailed，并保留 releasePageUri 供界面打开该 Release。底层异常写日志，界面仅使用设计文档中的中文错误；过期 generation 或 disposed 后不得发布状态。

- [ ] **Step 5: 验证并提交**

~~~powershell
flutter test --no-pub test/update/update_controller_test.dart
git add -- lib/update/update_controller.dart test/update/update_controller_test.dart
git commit -m "feat: coordinate automatic player updates"
~~~

Expected: 成功、失败、取消和并发测试全部 PASS。

---

### Task 7: Settings Update UI

**Files:**
- Modify: lib/page/settings_page/check_update.dart
- Create: test/page/check_update_test.dart

**Interfaces:**
- Consumes: Task 6 状态机。
- Produces: 手动检查、更新说明、进度、取消、重试和 Portable 回退界面。

- [ ] **Step 1: 写失败 Widget 测试**

~~~dart
testWidgets('installed edition offers one-click update', (tester) async {
  final controller = FakeUpdateController(
    UpdateAvailable(candidate, canAutoInstall: true),
  );

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: CheckForUpdate(controller: controller)),
  ));

  expect(find.byKey(const Key('install-update-button')), findsOneWidget);
  expect(find.text('立即更新'), findsOneWidget);
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
});
~~~

另测百分比、未知大小进度、仅下载阶段可取消、关闭下载窗口会取消、校验/准备文案、可重试失败、带 Release 页面地址的资产错误、哈希失败、无更新和双击保护。

- [ ] **Step 2: 运行测试确认红灯**

Run: flutter test --no-pub test/page/check_update_test.dart

Expected: FAIL，因为当前 Widget 不接受 controller，也不显示状态机。

- [ ] **Step 3: 接入可注入 controller**

~~~dart
class CheckForUpdate extends StatefulWidget {
  const CheckForUpdate({super.key, this.controller});
  final UpdateControllerView? controller;
}
~~~

内部仅 dispose 自己创建的生产 controller。监听器对每个候选只打开一次对话框。

- [ ] **Step 4: 实现已确认界面**

稳定 key：

~~~dart
const Key('check-update-button');
const Key('install-update-button');
const Key('cancel-update-download-button');
const Key('open-update-release-button');
const Key('retry-update-button');
const Key('update-download-progress');
~~~

安装版显示“暂不更新/立即更新”；Portable 显示说明和“下载新版本”；下载显示 LinearProgressIndicator 与可用百分比；取消只在下载状态出现；关闭下载窗口必须调用 cancelDownload；校验和准备显示已确认文案；失败仅在 canRetry 时显示重试，releasePageUri 非空时显示“打开发布页面”。Markdown、Portable 和失败回退链接可调用 launchInBrowser，但不得解析正文为命令。

- [ ] **Step 5: 验证并提交**

~~~powershell
flutter test --no-pub test/page/check_update_test.dart test/update/update_controller_test.dart test/update/update_service_test.dart
git add -- lib/page/settings_page/check_update.dart test/page/check_update_test.dart
git commit -m "feat: add one-click update progress UI"
~~~

Expected: Widget 与协调测试均 PASS。

---

### Task 8: Prepare Version .10 and Verify

**Files:**
- Modify: pubspec.yaml
- Modify: lib/release_info.dart
- Modify: test/release_info_test.dart
- Modify: .github/workflows/release.yml
- Modify: README.md
- Modify: .github/RELEASE_TEMPLATE.md

**Interfaces:**
- Consumes: Tasks 1–7。
- Produces: 可供单独授权后构建或发布的版本一致源码。

- [ ] **Step 1: 先把版本测试期望改为 .10**

~~~dart
expect(currentReleaseVersion, '1.5.1-kalin.10');
~~~

Run: flutter test --no-pub test/release_info_test.dart

Expected: FAIL，因为生产仍是 .9。

- [ ] **Step 2: 对齐版本**

~~~yaml
# pubspec.yaml
version: 1.5.1-kalin.10
~~~

~~~dart
// lib/release_info.dart
const currentReleaseVersion = '1.5.1-kalin.10';
~~~

~~~yaml
# release.yml workflow_dispatch default
default: v1.5.1-kalin.10
~~~

- [ ] **Step 3: 更新用户文档**

README 与 Release 模板明确：.9 → .10 最后一次手动覆盖且不卸载；.10 以后安装版使用“设置 → 检查更新 → 立即更新”；自动流程下载、校验、覆盖注册目录并重启；Portable 进入 Release 页面；用户数据位置不变。把“先卸载原版”收窄为仅针对首次从上游安装器迁移。

- [ ] **Step 4: 运行完整本地验证**

~~~powershell
flutter test --no-pub
dart analyze lib test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/release_helpers_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/installer_contract_test.ps1
git diff --check
~~~

Expected: 原有 195 项加新增测试全部 PASS；analyze exit 0 且无新增 warning/error；两个 PowerShell 测试输出 PASS；diff check 无输出。

- [ ] **Step 5: 提交发布准备**

~~~powershell
git add -- pubspec.yaml lib/release_info.dart test/release_info_test.dart .github/workflows/release.yml README.md .github/RELEASE_TEMPLATE.md
git commit -m "chore: prepare v1.5.1-kalin.10"
~~~

- [ ] **Step 6: 在用户授权后仅构建验证包**

手动 dispatch release.yml，输入 v1.5.1-kalin.10。该路径只上传 Actions artifact，不发布 Release。验证产物必须包含 Portable.zip、Setup.exe 和 SHA256SUMS.txt。将 Setup 覆盖安装到 .9，确认无需卸载、目录不变、用户数据保留、设置页识别为安装版。

- [ ] **Step 7: 停在发布边界**

报告验证结果。未经明确授权，不创建或推送标签、不发布 Release、不推送 main。

---

## Final Self-Review Checklist

- [ ] 所有已批准设计要求都有任务和测试覆盖。
- [ ] Release 选择拒绝草稿、预发布、非 HTTPS 和近似文件名。
- [ ] 安装版识别同时要求固定 AppId 和当前 EXE 目录匹配。
- [ ] 取消与失败路径清理不完整 .part。
- [ ] SHA-256 失败无法到达安装器启动。
- [ ] 保存或启动失败无法到达应用关闭。
- [ ] 更新命令不传 /DIR。
- [ ] Portable 不下载或运行 Setup。
- [ ] Inno 只在成功更新后重启播放器。
- [ ] 正常退出与更新退出共用一个实现。
- [ ] .10 版本、workflow、文档和测试一致。
- [ ] 构建验证不等于授权推送、打标签或发布。
