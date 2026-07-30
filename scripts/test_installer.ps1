param(
    [Parameter(Mandatory)][string] $InstallerPath,
    [Parameter(Mandatory)][string] $TestRoot
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'release_helpers.ps1')

$installerFullPath = if ([IO.Path]::IsPathRooted($InstallerPath)) {
    [IO.Path]::GetFullPath($InstallerPath)
}
else {
    [IO.Path]::GetFullPath((Join-Path $repositoryRoot $InstallerPath))
}
if (-not (Test-Path -LiteralPath $installerFullPath -PathType Leaf)) {
    throw "Installer not found: $installerFullPath"
}

$testRootFullPath = if ([IO.Path]::IsPathRooted($TestRoot)) {
    [IO.Path]::GetFullPath($TestRoot)
}
else {
    [IO.Path]::GetFullPath((Join-Path $repositoryRoot $TestRoot))
}
$safeBuildRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'build')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $testRootFullPath.StartsWith($safeBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Installer smoke-test directory must remain below '$safeBuildRoot'."
}

if (Test-Path -LiteralPath $testRootFullPath) {
    Remove-Item -LiteralPath $testRootFullPath -Recurse -Force
}
New-Item -ItemType Directory -Path $testRootFullPath -Force | Out-Null

Invoke-ProcessAndWait -FilePath $installerFullPath -ArgumentList @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    "/DIR=`"$testRootFullPath`""
)

Assert-ReleaseLayout $testRootFullPath
$uninstaller = Join-Path $testRootFullPath 'unins000.exe'
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
    throw "Uninstaller not found: $uninstaller"
}

Invoke-ProcessAndWait -FilePath $uninstaller -ArgumentList @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART'
)
if (Test-Path -LiteralPath (Join-Path $testRootFullPath 'coriander_player.exe')) {
    throw 'Player executable remains after silent uninstall.'
}

Write-Output 'installer_smoke_test: PASS'
