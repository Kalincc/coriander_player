# Automated Windows Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish `v1.5.1-kalin.1` as a reproducible GitHub Release containing a complete portable ZIP and an Inno Setup installer with the player, BASS runtime, and desktop lyric companion.

**Architecture:** Pure Dart helpers own fork release identity, version comparison, and issue URL construction. A PowerShell packaging layer builds and validates the Windows directory, while an Inno Setup definition wraps exactly that directory. A tag-triggered GitHub Actions workflow runs all tests and package checks before atomically creating the Release.

**Tech Stack:** Flutter 3.38.9, Dart, Rust/Cargo, PowerShell 7, Inno Setup 6, GitHub Actions, GitHub CLI.

## Global Constraints

- Release tags match `v<upstream-version>-kalin.<revision>`; the first tag is exactly `v1.5.1-kalin.1`.
- The main player uses Flutter 3.38.9.
- The desktop lyric source is pinned to `Ferry-200/desktop_lyric@fe84f66ba0b0e304b05c558483b37552c906cc06`.
- Release assets are named `Coriander.Player.<version>.Portable.zip`, `Coriander.Player.<version>.Setup.exe`, and `SHA256SUMS.txt`.
- The installer is unsigned, installs per user, leaves `Documents\coriander_player` untouched, and uses a fork-specific Inno Setup `AppId`.
- No GitHub token, feedback token, or other secret may be committed or embedded in an application binary.
- Every BASS archive is downloaded over HTTPS and rejected unless its SHA-256 matches the value recorded in Task 3.
- A failed test, build, layout check, installer check, or checksum step must prevent Release creation.

---

## File map

- `lib/release_info.dart`: fork repository identity and comparable fork release version value object.
- `test/release_info_test.dart`: parsing and ordering coverage for fork versions.
- `lib/app_settings.dart`: current fork version displayed by the app.
- `lib/page/settings_page/check_update.dart`: queries and compares releases from the fork.
- `lib/page/settings_page/issue_report.dart`: builds a token-free GitHub issue URL.
- `test/page/issue_report_test.dart`: verifies issue title, description, and log encoding.
- `lib/page/settings_page/create_issue.dart`: opens the fork issue URL instead of calling GitHub's issue API.
- `scripts/release_helpers.ps1`: tag parsing, SHA-256 checks, and package layout validation.
- `scripts/tests/release_helpers_test.ps1`: dependency-free PowerShell regression tests.
- `scripts/package_windows.ps1`: builds and assembles the complete portable directory and ZIP.
- `installer/coriander_player.iss`: per-user Inno Setup installer definition.
- `scripts/test_installer.ps1`: silent install, layout validation, and silent uninstall smoke test.
- `.github/RELEASE_TEMPLATE.md`: provenance, feature summary, and installation instructions.
- `.github/workflows/release.yml`: tag-triggered quality gates and publication.

---

### Task 1: Fork release identity and version comparison

**Files:**
- Create: `lib/release_info.dart`
- Create: `test/release_info_test.dart`
- Modify: `pubspec.yaml:4`
- Modify: `lib/app_settings.dart:31-39`
- Modify: `lib/page/settings_page/check_update.dart:29-55`

**Interfaces:**
- Produces: `currentReleaseVersion`, `releaseRepositoryOwner`, `releaseRepositoryName`, `releaseRepositoryUrl`, and `ForkReleaseVersion.parse(String)` / `tryParse(String)` / `compareTo(ForkReleaseVersion)`.
- Consumes: GitHub release tags returned by `package:github`.

- [ ] **Step 1: Write the failing Dart version tests**

Create `test/release_info_test.dart` with these cases:

```dart
import 'package:coriander_player/release_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the current fork tag with or without v prefix', () {
    expect(ForkReleaseVersion.parse('v1.5.1-kalin.1'),
        ForkReleaseVersion(1, 5, 1, 1));
    expect(ForkReleaseVersion.parse('1.5.1-kalin.1'),
        ForkReleaseVersion(1, 5, 1, 1));
  });

  test('orders upstream components before fork revision', () {
    expect(ForkReleaseVersion.parse('v1.5.1-kalin.2') >
        ForkReleaseVersion.parse('v1.5.1-kalin.1'), isTrue);
    expect(ForkReleaseVersion.parse('v1.6.0-kalin.1') >
        ForkReleaseVersion.parse('v1.5.9-kalin.99'), isTrue);
  });

  test('rejects tags outside the fork release scheme', () {
    expect(ForkReleaseVersion.tryParse('v1.5.1'), isNull);
    expect(ForkReleaseVersion.tryParse('latest'), isNull);
  });

  test('release constants point to the fork', () {
    expect(currentReleaseVersion, '1.5.1-kalin.1');
    expect(releaseRepositoryOwner, 'Kalincc');
    expect(releaseRepositoryName, 'coriander_player');
  });
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```powershell
D:\Development\flutter\bin\flutter.bat test test/release_info_test.dart
```

Expected: FAIL because `lib/release_info.dart` does not exist.

- [ ] **Step 3: Implement the release value object and constants**

Create `lib/release_info.dart` with an immutable four-component version. Use
this exact pattern and compare each component in order:

```dart
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
    if (parsed == null) throw FormatException('Invalid fork release: $value');
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
```

Set `pubspec.yaml` to `version: 1.5.1-kalin.1` and set
`AppSettings.version = currentReleaseVersion` after importing
`release_info.dart`.

- [ ] **Step 4: Point update checks to the fork**

In `check_update.dart`, construct
`RepositorySlug(releaseRepositoryOwner, releaseRepositoryName)`. Parse the
current version once, scan releases for the first tag accepted by
`ForkReleaseVersion.tryParse`, and show the dialog only when that parsed value
is greater than the current value. An empty or malformed release list must show
`无新版本`, while transport failures retain the existing `网络异常` behavior.

- [ ] **Step 5: Run focused and full tests**

Run:

```powershell
D:\Development\flutter\bin\flutter.bat test test/release_info_test.dart
D:\Development\flutter\bin\flutter.bat test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit Task 1**

```powershell
git add pubspec.yaml pubspec.lock lib/release_info.dart lib/app_settings.dart lib/page/settings_page/check_update.dart test/release_info_test.dart
git commit -m "feat: track fork release versions"
```

---

### Task 2: Token-free issue reporting to the fork

**Files:**
- Create: `lib/page/settings_page/issue_report.dart`
- Create: `test/page/issue_report_test.dart`
- Modify: `lib/page/settings_page/create_issue.dart`

**Interfaces:**
- Consumes: `releaseRepositoryUrl` from Task 1 and the existing title, description, and in-memory log fields.
- Produces: `Uri buildIssueReportUri({required String title, required String description, required String log})`.

- [ ] **Step 1: Write the failing issue URL test**

```dart
import 'package:coriander_player/page/settings_page/issue_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a prefilled issue URL for the fork', () {
    final uri = buildIssueReportUri(
      title: '歌词搜索异常',
      description: '输入周杰伦后没有结果',
      log: 'line 1\nline 2',
    );

    expect(uri.host, 'github.com');
    expect(uri.path, '/Kalincc/coriander_player/issues/new');
    expect(uri.queryParameters['title'], '歌词搜索异常');
    expect(uri.queryParameters['body'], contains('## 描述'));
    expect(uri.queryParameters['body'], contains('输入周杰伦后没有结果'));
    expect(uri.queryParameters['body'], contains('```\nline 1\nline 2\n```'));
  });
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

```powershell
D:\Development\flutter\bin\flutter.bat test test/page/issue_report_test.dart
```

Expected: FAIL because `issue_report.dart` does not exist.

- [ ] **Step 3: Implement the pure URL builder**

Create `issue_report.dart` using `Uri.https` so all user text is encoded:

```dart
import 'package:coriander_player/release_info.dart';

Uri buildIssueReportUri({
  required String title,
  required String description,
  required String log,
}) {
  final body = StringBuffer()
    ..writeln('## 描述')
    ..writeln(description)
    ..writeln()
    ..writeln('## 日志')
    ..writeln('```')
    ..writeln(log)
    ..writeln('```');
  return Uri.https(
    'github.com',
    '/$releaseRepositoryOwner/$releaseRepositoryName/issues/new',
    {'title': title, 'body': body.toString()},
  );
}
```

- [ ] **Step 4: Replace authenticated issue submission**

Remove imports of `package:github/github.dart` and `cpfeedback_key.dart` from
`create_issue.dart`. Keep the existing form, but make `createIssue()` call
`buildIssueReportUri`, then `launchInBrowser(uri: uri.toString())`. Re-enable the
button in `finally`; show `已在浏览器打开` on `true` and `无法打开浏览器` on
`false`. This removes the build-time dependency on the ignored feedback key.

- [ ] **Step 5: Run focused and full tests**

```powershell
D:\Development\flutter\bin\flutter.bat test test/page/issue_report_test.dart
D:\Development\flutter\bin\flutter.bat test
```

Expected: all tests PASS and no production file imports `cpfeedback_key.dart`.

- [ ] **Step 6: Commit Task 2**

```powershell
git add lib/page/settings_page/create_issue.dart lib/page/settings_page/issue_report.dart test/page/issue_report_test.dart
git commit -m "fix: report fork issues without a token"
```

---

### Task 3: Reproducible portable package assembly

**Files:**
- Create: `scripts/release_helpers.ps1`
- Create: `scripts/tests/release_helpers_test.ps1`
- Create: `scripts/package_windows.ps1`

**Interfaces:**
- Produces: `ConvertFrom-ForkReleaseTag`, `Assert-FileSha256`, and `Assert-ReleaseLayout`; creates `dist/stage/Coriander Player/` and `dist/Coriander.Player.<version>.Portable.zip`.
- Consumes: tag string, Flutter on `PATH`, Git, pinned desktop lyric commit, and the eight HTTPS BASS archives listed below.

- [ ] **Step 1: Write dependency-free failing PowerShell tests**

The test script dot-sources `release_helpers.ps1`, creates a uniquely named
directory below `[IO.Path]::GetTempPath()`, and uses a local `Assert-Equal`
function that throws on mismatch. Cover these cases:

```powershell
$version = ConvertFrom-ForkReleaseTag 'v1.5.1-kalin.1'
Assert-Equal $version '1.5.1-kalin.1'
Assert-Throws { ConvertFrom-ForkReleaseTag 'v1.5.1' }
Assert-Throws { Assert-FileSha256 $fixture '0000' }
Assert-Throws { Assert-ReleaseLayout $emptyRoot }
Assert-ReleaseLayout $completeFixtureRoot
```

The complete fixture must create the exact required tree shown in the design,
including all eight BASS DLL names and the three required desktop lyric paths.
Delete only the uniquely created test directory in a `finally` block.

- [ ] **Step 2: Run the helper test and verify it fails**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/release_helpers_test.ps1
```

Expected: FAIL because `release_helpers.ps1` does not exist.

- [ ] **Step 3: Implement the release helpers**

`ConvertFrom-ForkReleaseTag` must match
`^v(?<version>\d+\.\d+\.\d+-kalin\.\d+)$` and return only the named version.
`Assert-FileSha256` compares an uppercase `Get-FileHash -Algorithm SHA256`
value. `Assert-ReleaseLayout` calls `Test-Path -PathType Leaf/Container` for
every required path and throws one message listing all missing relative paths.
Set `$ErrorActionPreference = 'Stop'` in all release scripts.

- [ ] **Step 4: Run the helper tests and verify they pass**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/release_helpers_test.ps1
```

Expected: PASS with a final `release_helpers_test: PASS` line.

- [ ] **Step 5: Implement the packaging script**

Use parameters `-Tag` and optional `-OutputDirectory` (default `dist`). The
script must:

1. Parse the tag and compare it to `version:` in `pubspec.yaml`.
2. Remove and recreate only `build/release-work` and the selected output
   directory after resolving both paths beneath the repository root.
3. Run `flutter pub get` and `flutter build windows --release` for the player.
4. Clone `Ferry-200/desktop_lyric`, detach checkout at
   `fe84f66ba0b0e304b05c558483b37552c906cc06`, and run the same Flutter build.
5. Download and verify these exact archives:

```powershell
$bassArchives = @(
  @{ Name='bass24.zip'; Url='https://www.un4seen.com/files/bass24.zip'; Sha256='3A03EC9A33D0F4F9D167660DA51C8BB1432E8977496995455AB137277D69636E' },
  @{ Name='bassape24.zip'; Url='https://www.un4seen.com/files/bassape24.zip'; Sha256='39AED2E9AC240253DE0ECA37D261715B85CC7937504447083E2ED6690256B770' },
  @{ Name='bassdsd24.zip'; Url='https://www.un4seen.com/files/bassdsd24.zip'; Sha256='480DAB317518E819A573C2BE40FD4CAFA30B41A1D6DC0D27D4F1A3BCC654D8B6' },
  @{ Name='bassflac24.zip'; Url='https://www.un4seen.com/files/bassflac24.zip'; Sha256='147280210F62A80E52094E1822E73A16FD3B1A8C9C857C24DCCA7DCFCB4FFA14' },
  @{ Name='bassmidi24.zip'; Url='https://www.un4seen.com/files/bassmidi24.zip'; Sha256='317EC770D71266B5294543D7C87CBBB39ABA38BC8BC623AF518A96C670392234' },
  @{ Name='bassopus24.zip'; Url='https://www.un4seen.com/files/bassopus24.zip'; Sha256='1FB6E033289EA968CA1FD02DEA154A2E5D06BB9C2E33CDEDA277E63084D9AD20' },
  @{ Name='basswv24.zip'; Url='https://www.un4seen.com/files/basswv24.zip'; Sha256='48E59F6136DB90BDE01E790273E3713AC6B0C6B1964174DC15F338F5180B9ECF' },
  @{ Name='basswasapi24.zip'; Url='https://www.un4seen.com/files/basswasapi24.zip'; Sha256='4BA99200EBEF8DCA11CC99CBA9B5DC3E51A1C467E570DE2CBC0631A038F7EA2D' }
)
```

6. Extract only each archive's `x64/*.dll` into `BASS/`.
7. Copy the full player Release tree into the stage root and the full desktop
   lyric Release tree into `desktop_lyric/`.
8. Call `Assert-ReleaseLayout` and only then create the portable ZIP.
9. Print machine-readable `VERSION=`, `STAGE_DIR=`, and `ZIP_PATH=` lines for
   the workflow.

- [ ] **Step 6: Exercise the real package build locally**

```powershell
$env:Path = "D:\Development\flutter\bin;$env:Path"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package_windows.ps1 -Tag v1.5.1-kalin.1
```

Expected: exit 0, a validated stage directory, and
`dist/Coriander.Player.1.5.1-kalin.1.Portable.zip`.

- [ ] **Step 7: Commit Task 3**

```powershell
git add scripts/release_helpers.ps1 scripts/tests/release_helpers_test.ps1 scripts/package_windows.ps1
git commit -m "build: assemble complete Windows package"
```

---

### Task 4: Inno Setup installer and smoke test

**Files:**
- Create: `installer/coriander_player.iss`
- Create: `scripts/test_installer.ps1`

**Interfaces:**
- Consumes: `CORIANDER_RELEASE_VERSION`, `CORIANDER_STAGE_DIR`, and `CORIANDER_OUTPUT_DIR` environment variables plus Task 3's validated stage.
- Produces: `Coriander.Player.<version>.Setup.exe` and an exit-code-based silent install/uninstall verification.

- [ ] **Step 1: Write the installer smoke script before the installer definition**

Accept mandatory `-InstallerPath` and `-TestRoot`. Resolve both to absolute
paths. Create only `$TestRoot`, invoke the installer with
`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="$TestRoot"`, call
`Assert-ReleaseLayout $TestRoot`, require `$TestRoot\unins000.exe`, invoke it
with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`, and verify that
`coriander_player.exe` no longer exists. Throw on every nonzero process exit.

- [ ] **Step 2: Verify the smoke test fails before an installer exists**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_installer.ps1 -InstallerPath dist/missing.exe -TestRoot build/installer-smoke
```

Expected: FAIL with `Installer not found`.

- [ ] **Step 3: Implement the Inno Setup definition**

Use these fixed properties:

```ini
#define AppVersion GetEnv("CORIANDER_RELEASE_VERSION")
#define StageDir GetEnv("CORIANDER_STAGE_DIR")
#define ArtifactDir GetEnv("CORIANDER_OUTPUT_DIR")

[Setup]
AppId={{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}
AppName=Coriander Player
AppVersion={#AppVersion}
AppPublisher=Kalincc
AppPublisherURL=https://github.com/Kalincc/coriander_player
DefaultDirName={localappdata}\Programs\Coriander Player
DefaultGroupName=Coriander Player
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#ArtifactDir}
OutputBaseFilename=Coriander.Player.{#AppVersion}.Setup
SetupIconFile=..\app_icon.ico
UninstallDisplayIcon={app}\coriander_player.exe
Compression=lzma2/ultra64
SolidCompression=yes
CloseApplications=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式:"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Coriander Player"; Filename: "{app}\coriander_player.exe"
Name: "{autodesktop}\Coriander Player"; Filename: "{app}\coriander_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\coriander_player.exe"; Description: "启动 Coriander Player"; Flags: nowait postinstall skipifsilent
```

- [ ] **Step 4: Compile and smoke-test the installer locally**

```powershell
$env:CORIANDER_RELEASE_VERSION = '1.5.1-kalin.1'
$env:CORIANDER_STAGE_DIR = (Resolve-Path 'dist/stage/Coriander Player').Path
$env:CORIANDER_OUTPUT_DIR = (Resolve-Path 'dist').Path
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' installer/coriander_player.iss
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_installer.ps1 -InstallerPath dist/Coriander.Player.1.5.1-kalin.1.Setup.exe -TestRoot build/installer-smoke
```

Expected: compiler exit 0, smoke script exit 0, and no player executable left
under `build/installer-smoke` after uninstall.

- [ ] **Step 5: Commit Task 4**

```powershell
git add installer/coriander_player.iss scripts/test_installer.ps1
git commit -m "build: add Windows setup package"
```

---

### Task 5: Tag-triggered GitHub Release workflow

**Files:**
- Create: `.github/RELEASE_TEMPLATE.md`
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: Tasks 1-4, the pushed release tag, GitHub's built-in `GITHUB_TOKEN`, Flutter 3.38.9, Rust stable, and Inno Setup 6.
- Produces: one published GitHub Release with the portable ZIP, installer, and checksum file.

- [ ] **Step 1: Write the release template**

The Markdown must link to
`https://github.com/Ferry-200/coriander_player`, identify this as the
`Kalincc` enhancement fork, list the three enhancements, explain ZIP and Setup
usage, state that `desktop_lyric` and BASS are included, and warn that the
unsigned installer can trigger SmartScreen.

- [ ] **Step 2: Create the workflow through the pre-publication steps**

Configure:

```yaml
name: Release Windows packages
on:
  push:
    tags:
      - 'v*-kalin.*'
permissions:
  contents: write
jobs:
  release:
    runs-on: windows-latest
```

Use `actions/checkout@v4`, `dtolnay/rust-toolchain@stable`, and
`subosito/flutter-action@v2` with `flutter-version: '3.38.9'` and cache enabled.
Run, in order:

```powershell
flutter pub get
flutter test
cargo check --manifest-path rust/Cargo.toml
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/release_helpers_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package_windows.ps1 -Tag $env:GITHUB_REF_NAME
choco install innosetup --no-progress -y
```

Then compile the installer using the environment contract from Task 4, smoke
test it under `build/installer-smoke`, and generate lowercase SHA-256 lines in
`dist/SHA256SUMS.txt` for exactly the ZIP and Setup EXE.

- [ ] **Step 3: Add artifact retention and the final atomic publish step**

Upload the three files with `actions/upload-artifact@v4` and
`if: ${{ always() && hashFiles('dist/*') != '' }}` for diagnostics. The final
step runs only after all prior steps succeeded:

```powershell
gh release create $env:GITHUB_REF_NAME `
  "dist/Coriander.Player.$version.Portable.zip" `
  "dist/Coriander.Player.$version.Setup.exe" `
  "dist/SHA256SUMS.txt" `
  --repo "$env:GITHUB_REPOSITORY" `
  --title "Coriander Player $version" `
  --notes-file ".github/RELEASE_TEMPLATE.md" `
  --verify-tag
```

Set `GH_TOKEN: ${{ github.token }}` only on this publication step. Do not use
`continue-on-error` anywhere in the release job.

- [ ] **Step 4: Validate workflow syntax and local quality gates**

Run:

```powershell
D:\Development\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\Development\flutter\bin\flutter.bat analyze
D:\Development\flutter\bin\flutter.bat test
cargo check --manifest-path rust/Cargo.toml
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/release_helpers_test.ps1
git diff --check
```

Install and run a fixed `actionlint` release, then require exit 0:

```powershell
go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
$actionlint = Join-Path (go env GOPATH) 'bin\actionlint.exe'
& $actionlint .github/workflows/release.yml
```

- [ ] **Step 5: Commit Task 5**

```powershell
git add .github/RELEASE_TEMPLATE.md .github/workflows/release.yml
git commit -m "ci: publish Windows release packages"
```

---

### Task 6: Publish and independently verify `v1.5.1-kalin.1`

**Files:**
- Verify only: all files committed in Tasks 1-5

**Interfaces:**
- Consumes: clean `main`, authenticated `gh`, `origin` set to `Kalincc/coriander_player`, and successful local checks.
- Produces: pushed `main`, annotated tag `v1.5.1-kalin.1`, completed Actions run, and verified public Release assets.

- [ ] **Step 1: Verify repository and release preconditions**

```powershell
git status --short --branch
git remote -v
git log --oneline origin/main..HEAD
gh auth status
gh release view v1.5.1-kalin.1 --repo Kalincc/coriander_player
```

Expected: clean worktree; `origin` is the fork; authenticated user is
`Kalincc`; the release lookup fails because the tag and Release do not yet
exist.

- [ ] **Step 2: Push implementation commits before creating a tag**

```powershell
git push origin main
```

Expected: remote `main` reaches local `HEAD`.

- [ ] **Step 3: Create and push the annotated release tag**

```powershell
git tag -a v1.5.1-kalin.1 -m "Coriander Player 1.5.1-kalin.1"
git push origin v1.5.1-kalin.1
```

Expected: the tag points to the verified `main` commit and triggers
`Release Windows packages`.

- [ ] **Step 4: Wait for the workflow and inspect failures if necessary**

```powershell
$runId = gh run list --repo Kalincc/coriander_player --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $runId --repo Kalincc/coriander_player --exit-status
```

Expected: the tagged workflow completes successfully. If it fails, inspect
with `gh run view $runId --repo Kalincc/coriander_player --log-failed`. Fix on
`main`; confirm `gh release view v1.5.1-kalin.1` still returns not found and
confirm the tag points to the failed commit before deleting only that local and
remote tag, then retag the corrected commit and rerun this step.

- [ ] **Step 5: Verify the published Release and checksums independently**

Download into a new uniquely named temporary directory:

```powershell
$verifyDir = Join-Path $env:TEMP ('coriander-release-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $verifyDir | Out-Null
gh release download v1.5.1-kalin.1 --repo Kalincc/coriander_player --dir $verifyDir
Get-ChildItem $verifyDir
Get-Content (Join-Path $verifyDir 'SHA256SUMS.txt')
Get-FileHash -Algorithm SHA256 (Join-Path $verifyDir 'Coriander.Player.1.5.1-kalin.1.Portable.zip')
Get-FileHash -Algorithm SHA256 (Join-Path $verifyDir 'Coriander.Player.1.5.1-kalin.1.Setup.exe')
```

Expected: all three named assets exist and both computed hashes match
`SHA256SUMS.txt`. Open the ZIP listing and verify the required layout without
executing the downloaded application.

- [ ] **Step 6: Final repository verification**

```powershell
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
gh release view v1.5.1-kalin.1 --repo Kalincc/coriander_player --json url,tagName,isDraft,isPrerelease,assets
```

Expected: clean worktree, matching local and remote SHAs, `isDraft: false`, and
the three release assets. Record the Release URL in the handoff.
