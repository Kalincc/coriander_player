$ErrorActionPreference = 'Stop'

function ConvertFrom-ForkReleaseTag {
    param([Parameter(Mandatory)][string] $Tag)

    $match = [regex]::Match(
        $Tag,
        '^v(?<version>\d+\.\d+\.\d+-kalin\.\d+)$'
    )
    if (-not $match.Success) {
        throw "Invalid release tag '$Tag'. Expected v<major>.<minor>.<patch>-kalin.<revision>."
    }
    return $match.Groups['version'].Value
}

function Assert-FileSha256 {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Expected
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found for SHA-256 verification: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    $normalizedExpected = $Expected.ToUpperInvariant()
    if ($actual -ne $normalizedExpected) {
        throw "SHA-256 mismatch for '$Path'. Expected $normalizedExpected, got $actual."
    }
}

function Assert-ReleaseLayout {
    param([Parameter(Mandatory)][string] $Root)

    $requiredDirectories = @(
        'data',
        'desktop_lyric\data'
    )
    $requiredFiles = @(
        'coriander_player.exe',
        'flutter_windows.dll',
        'BASS\bass.dll',
        'BASS\bassape.dll',
        'BASS\bassdsd.dll',
        'BASS\bassflac.dll',
        'BASS\bassmidi.dll',
        'BASS\bassopus.dll',
        'BASS\basswasapi.dll',
        'BASS\basswv.dll',
        'desktop_lyric\desktop_lyric.exe',
        'desktop_lyric\flutter_windows.dll'
    )

    $missing = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in $requiredDirectories) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Container)) {
            $missing.Add($relativePath)
        }
    }
    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
            $missing.Add($relativePath)
        }
    }
    if ($missing.Count -gt 0) {
        throw "Release layout is incomplete. Missing: $($missing -join ', ')"
    }
}
