# Coriander Player Fork Windows Release Design

## Goal

Provide a repeatable Windows release process for the `Kalincc/coriander_player`
fork. Pushing a version tag must build and publish both a complete portable ZIP
and a conventional Windows installer containing the player, BASS libraries, and
the desktop lyric companion.

The first release is `v1.5.1-kalin.1` and is based on
[`Ferry-200/coriander_player`](https://github.com/Ferry-200/coriander_player).

## User-facing scope

The release contains the fork's three enhancements:

1. Search local lyrics and show grouped song information plus matching lyric
   snippets without automatically starting playback.
2. Vertically center the active lyric in the now-playing view.
3. Display albums without grouping or grouped by artist.

The release notes and repository documentation must identify the upstream
project and summarize these changes.

## Release architecture

The repository will add three release components:

- `scripts/package_windows.ps1` builds the two Flutter applications, downloads
  the BASS runtime from the same official source used by the upstream workflow,
  validates the runtime layout, and creates the portable ZIP.
- `installer/coriander_player.iss` describes an Inno Setup installer over the
  validated portable directory.
- `.github/workflows/release.yml` runs for tags matching `v*-kalin.*`, executes
  all quality gates, builds the installer, computes checksums, and creates the
  GitHub Release only after every preceding step succeeds.

The main player is built with Flutter 3.38.9. The desktop lyric component is
checked out from `Ferry-200/desktop_lyric` at immutable commit
`fe84f66ba0b0e304b05c558483b37552c906cc06` so repeated builds do not silently
change when its upstream branch changes.

## Packaged directory layout

The validated portable root contains at least:

```text
coriander_player.exe
data/
flutter_windows.dll
BASS/
  bass.dll
  bassape.dll
  bassdsd.dll
  bassflac.dll
  bassmidi.dll
  bassopus.dll
  basswasapi.dll
  basswv.dll
desktop_lyric/
  desktop_lyric.exe
  data/
  flutter_windows.dll
```

Other plugin DLLs emitted by Flutter remain beside the appropriate executable.
The packaging script fails if a required file or directory is absent.

## Fork release integration

The in-app update checker will read Releases from `Kalincc/coriander_player`
instead of the upstream repository. It will compare fork versions containing a
prerelease suffix such as `1.5.1-kalin.1`, allowing later `kalin.2` releases to
be detected correctly. The displayed current version will use the same version
source as the package metadata.

The in-app issue action will open the new-issue page for
`Kalincc/coriander_player`. It will not embed a GitHub token or submit issues to
the upstream repository.

## Release artifacts

The `v1.5.1-kalin.1` release will contain:

- `Coriander.Player.1.5.1-kalin.1.Portable.zip`
- `Coriander.Player.1.5.1-kalin.1.Setup.exe`
- `SHA256SUMS.txt`

GitHub's automatically generated source archives may also appear. The release
body identifies the upstream project, lists the fork enhancements, documents
portable and installer usage, and notes that the binaries are unsigned.

## Installer behavior

The Inno Setup installer uses a fork-specific application identifier so it does
not claim ownership of the upstream installer's uninstall entry. Its display
name remains `Coriander Player` and the installation directory is selectable.
The default is `%LocalAppData%\Programs\Coriander Player`; the user can select
their previous directory,
`D:\新装的软件\musci player\Coriander Player`, after manually removing the
upstream installation.

The installer:

- installs for the current user without requiring administrator rights;
- creates a Start menu shortcut and offers an optional desktop shortcut;
- registers an independent uninstaller;
- prompts appropriately if the player is running;
- never deletes or owns the application data under
  `Documents\coriander_player`.

No paid code-signing certificate is in scope. Windows may therefore show a
SmartScreen warning. Signing can be added later through protected CI secrets
without changing the package layout.

## Versioning and trigger rules

Release tags use `v<upstream-version>-kalin.<revision>`, beginning with
`v1.5.1-kalin.1`. The workflow rejects tags that do not match the version in the
application metadata. A release is created from the exact tagged commit, never
from a moving branch.

Only tag pushes matching `v*-kalin.*` publish a Release. Pull requests and
ordinary branch pushes may run tests but cannot publish assets.

## Quality gates

Before publication the workflow must pass all of the following:

1. Flutter dependency resolution and the complete Flutter test suite.
2. Rust `cargo check`.
3. Windows release builds for the player and desktop lyric companion.
4. Validation of the full portable directory and all eight required BASS DLLs.
5. Portable ZIP creation and Inno Setup compilation.
6. SHA-256 generation for both binary artifacts.
7. Silent installation into an isolated temporary directory, followed by a
   required-file check and silent uninstall.

Any failure stops the workflow before the GitHub Release step. Intermediate
artifacts and logs remain available through the Actions run for diagnosis.

## Security and provenance

- GitHub's built-in workflow token receives only the permissions required to
  create release contents.
- No personal access token or feedback token is committed or embedded.
- Third-party downloads use HTTPS. Implementation records the SHA-256 of every
  downloaded archive in the packaging script and rejects any mismatch before
  extraction.
- The desktop lyric source is pinned to a commit and the Release notes link to
  both upstream repositories.

## Success criteria

The design is complete when pushing `v1.5.1-kalin.1` to the fork produces one
published GitHub Release whose ZIP runs as a portable application and whose
installer installs the same complete file tree to a user-selected directory.
Both packages expose the three fork enhancements, include desktop lyrics and
BASS playback support, point updates and issue reporting at the fork, and have
matching SHA-256 entries.
