$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$installerPath = Join-Path $repositoryRoot 'installer\coriander_player.iss'
$content = Get-Content -LiteralPath $installerPath -Raw

$requiredPatterns = @(
    'AppId={{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}',
    'PrivilegesRequired=lowest',
    'CORIANDERAPPUPDATE',
    'Check: IsAppUpdate'
)

foreach ($pattern in $requiredPatterns) {
    if (-not $content.Contains($pattern)) {
        throw "Installer contract is missing '$pattern'."
    }
}

$runSection = [regex]::Match($content, '(?ms)^\[Run\].*?(?=^\[|\z)').Value
if (-not $runSection.Contains('skipifsilent')) {
    throw 'The normal post-install launch must retain skipifsilent.'
}
if (-not $runSection.Contains('Check: IsAppUpdate')) {
    throw 'The update-only relaunch entry is missing.'
}

Write-Output 'installer_contract_test: PASS'
