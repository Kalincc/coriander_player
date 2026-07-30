param(
    [Parameter(Mandatory)][string] $Tag,
    [string] $OutputDirectory = 'dist'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'release_helpers.ps1')

function Assert-RepositoryChildPath {
    param([Parameter(Mandatory)][string] $Path)

    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $repositoryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release path must remain below the repository root: $resolved"
    }
    return $resolved
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string] $Command,
        [Parameter(ValueFromRemainingArguments)][string[]] $Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Command $($Arguments -join ' ')"
    }
}

function Reset-Directory {
    param([Parameter(Mandatory)][string] $Path)

    $safePath = Assert-RepositoryChildPath $Path
    if (Test-Path -LiteralPath $safePath) {
        Remove-Item -LiteralPath $safePath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $safePath -Force | Out-Null
    return $safePath
}

$version = ConvertFrom-ForkReleaseTag $Tag
$pubspecMatch = Select-String -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if ($null -eq $pubspecMatch) {
    throw 'pubspec.yaml does not contain a version field.'
}
$pubspecVersion = $pubspecMatch.Matches[0].Groups[1].Value
if ($pubspecVersion -ne $version) {
    throw "Tag version '$version' does not match pubspec version '$pubspecVersion'."
}

$workRoot = Reset-Directory (Join-Path $repositoryRoot 'build\release-work')
$outputRootCandidate = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
}
else {
    Join-Path $repositoryRoot $OutputDirectory
}
$outputRoot = Reset-Directory $outputRootCandidate
$stageRoot = Join-Path $outputRoot 'stage\Coriander Player'
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Push-Location $repositoryRoot
try {
    Invoke-Checked 'flutter' 'pub' 'get'
    Invoke-Checked 'flutter' 'build' 'windows' '--release'
}
finally {
    Pop-Location
}

$playerRelease = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $playerRelease -PathType Container)) {
    throw "Player Release directory not found: $playerRelease"
}
Copy-Item -Path (Join-Path $playerRelease '*') -Destination $stageRoot -Recurse -Force

$desktopLyricSource = Join-Path $workRoot 'desktop_lyric-src'
Invoke-Checked 'git' 'clone' '--no-checkout' 'https://github.com/Ferry-200/desktop_lyric.git' $desktopLyricSource
Invoke-Checked 'git' '-C' $desktopLyricSource 'fetch' '--depth' '1' 'origin' 'fe84f66ba0b0e304b05c558483b37552c906cc06'
Invoke-Checked 'git' '-C' $desktopLyricSource 'checkout' '--detach' 'FETCH_HEAD'

Push-Location $desktopLyricSource
try {
    Invoke-Checked 'flutter' 'pub' 'get'
    Invoke-Checked 'flutter' 'build' 'windows' '--release'
}
finally {
    Pop-Location
}

$desktopLyricRelease = Join-Path $desktopLyricSource 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $desktopLyricRelease -PathType Container)) {
    throw "Desktop lyric Release directory not found: $desktopLyricRelease"
}
$desktopLyricTarget = Join-Path $stageRoot 'desktop_lyric'
New-Item -ItemType Directory -Path $desktopLyricTarget -Force | Out-Null
Copy-Item -Path (Join-Path $desktopLyricRelease '*') -Destination $desktopLyricTarget -Recurse -Force

$bassArchives = @(
    @{ Name = 'bass24.zip'; Url = 'https://www.un4seen.com/files/bass24.zip'; Sha256 = '3A03EC9A33D0F4F9D167660DA51C8BB1432E8977496995455AB137277D69636E' },
    @{ Name = 'bassape24.zip'; Url = 'https://www.un4seen.com/files/bassape24.zip'; Sha256 = '39AED2E9AC240253DE0ECA37D261715B85CC7937504447083E2ED6690256B770' },
    @{ Name = 'bassdsd24.zip'; Url = 'https://www.un4seen.com/files/bassdsd24.zip'; Sha256 = '480DAB317518E819A573C2BE40FD4CAFA30B41A1D6DC0D27D4F1A3BCC654D8B6' },
    @{ Name = 'bassflac24.zip'; Url = 'https://www.un4seen.com/files/bassflac24.zip'; Sha256 = '147280210F62A80E52094E1822E73A16FD3B1A8C9C857C24DCCA7DCFCB4FFA14' },
    @{ Name = 'bassmidi24.zip'; Url = 'https://www.un4seen.com/files/bassmidi24.zip'; Sha256 = '317EC770D71266B5294543D7C87CBBB39ABA38BC8BC623AF518A96C670392234' },
    @{ Name = 'bassopus24.zip'; Url = 'https://www.un4seen.com/files/bassopus24.zip'; Sha256 = '1FB6E033289EA968CA1FD02DEA154A2E5D06BB9C2E33CDEDA277E63084D9AD20' },
    @{ Name = 'basswv24.zip'; Url = 'https://www.un4seen.com/files/basswv24.zip'; Sha256 = '48E59F6136DB90BDE01E790273E3713AC6B0C6B1964174DC15F338F5180B9ECF' },
    @{ Name = 'basswasapi24.zip'; Url = 'https://www.un4seen.com/files/basswasapi24.zip'; Sha256 = '4BA99200EBEF8DCA11CC99CBA9B5DC3E51A1C467E570DE2CBC0631A038F7EA2D' }
)

$bassDownloadRoot = Join-Path $workRoot 'bass'
$bassTarget = Join-Path $stageRoot 'BASS'
New-Item -ItemType Directory -Path $bassDownloadRoot, $bassTarget -Force | Out-Null
foreach ($archive in $bassArchives) {
    $archivePath = Join-Path $bassDownloadRoot $archive.Name
    Invoke-WebRequest -Uri $archive.Url -OutFile $archivePath
    Assert-FileSha256 $archivePath $archive.Sha256

    $extractRoot = Join-Path $bassDownloadRoot ([IO.Path]::GetFileNameWithoutExtension($archive.Name))
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    $x64Directory = Join-Path $extractRoot 'x64'
    $dlls = @(Get-ChildItem -LiteralPath $x64Directory -Filter '*.dll' -File)
    if ($dlls.Count -eq 0) {
        throw "No x64 DLL found in $($archive.Name)."
    }
    Copy-Item -LiteralPath $dlls.FullName -Destination $bassTarget -Force
}

Assert-ReleaseLayout $stageRoot

$zipPath = Join-Path $outputRoot "Coriander.Player.$version.Portable.zip"
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

Write-Output "VERSION=$version"
Write-Output "STAGE_DIR=$stageRoot"
Write-Output "ZIP_PATH=$zipPath"
