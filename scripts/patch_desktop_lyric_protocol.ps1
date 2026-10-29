param(
    [Parameter(Mandatory)][string] $Path
)

$ErrorActionPreference = 'Stop'

$sourceRoot = [IO.Path]::GetFullPath($Path)
$controllerPath = Join-Path $sourceRoot 'lib\desktop_lyric_controller.dart'
if (-not (Test-Path -LiteralPath $controllerPath -PathType Leaf)) {
    throw "Desktop lyric controller was not found: $controllerPath"
}

$source = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
if ($source.Contains('LineSplitter')) {
    throw "Desktop lyric controller is already patched or has an unexpected protocol implementation: $controllerPath"
}

$needle = 'stdin.transform(utf8.decoder).listen((event) {'
$occurrences = ([regex]::Matches($source, [regex]::Escape($needle))).Count
if ($occurrences -ne 1) {
    throw "Expected exactly one raw desktop lyric parser in $controllerPath, found $occurrences."
}

$replacement = @'
    stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((event) {
'@
$patched = $source.Replace($needle, $replacement.TrimEnd("`r", "`n"))

$actionPath = Join-Path $sourceRoot 'lib\component\action_row.dart'
$actions = Get-Content -LiteralPath $actionPath -Raw -Encoding utf8
$controlWrites = ([regex]::Matches($actions, [regex]::Escape('stdout.write('))).Count
if ($controlWrites -ne 5) {
    throw "Expected five unframed control messages in $actionPath, found $controlWrites."
}
$patchedActions = $actions.Replace('stdout.write(', 'stdout.writeln(')

Set-Content -LiteralPath $controllerPath -Value $patched -Encoding utf8 -NoNewline
Set-Content -LiteralPath $actionPath -Value $patchedActions -Encoding utf8 -NoNewline

Write-Output "Patched desktop lyric protocol: $controllerPath"
