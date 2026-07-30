$ErrorActionPreference = 'Stop'

$scriptsDirectory = Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsDirectory 'release_helpers.ps1')

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] $Expected
    )
    if ($Actual -ne $Expected) {
        throw "Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock] $Action)
    try {
        & $Action
    }
    catch {
        return
    }
    throw 'Expected the action to throw.'
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'coriander-release-helper-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    Assert-Equal (ConvertFrom-ForkReleaseTag 'v1.5.1-kalin.1') '1.5.1-kalin.1'
    Assert-Throws { ConvertFrom-ForkReleaseTag 'v1.5.1' }

    $hashFixture = Join-Path $fixtureRoot 'hash.txt'
    Set-Content -LiteralPath $hashFixture -Value 'hash fixture' -NoNewline
    Assert-Throws { Assert-FileSha256 $hashFixture ('0' * 64) }

    $emptyRoot = Join-Path $fixtureRoot 'empty'
    New-Item -ItemType Directory -Path $emptyRoot | Out-Null
    Assert-Throws { Assert-ReleaseLayout $emptyRoot }

    $completeRoot = Join-Path $fixtureRoot 'complete'
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
    New-Item -ItemType Directory -Path (Join-Path $completeRoot 'data') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $completeRoot 'desktop_lyric\data') -Force | Out-Null
    foreach ($relativePath in $requiredFiles) {
        $filePath = Join-Path $completeRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $filePath) -Force | Out-Null
        Set-Content -LiteralPath $filePath -Value '' -NoNewline
    }
    Assert-ReleaseLayout $completeRoot

    Write-Output 'release_helpers_test: PASS'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
