$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\patch_desktop_lyric_protocol.ps1'
$testRoot = Join-Path $env:TEMP "coriander-desktop-lyric-protocol-$([guid]::NewGuid().ToString('N'))"

function New-ControllerFixture {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $Content
    )

    $lib = Join-Path $Root 'lib'
    New-Item -ItemType Directory -Path $lib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $lib 'desktop_lyric_controller.dart') `
        -Value $Content -Encoding utf8
}

try {
    $controller = @'
import 'dart:convert';
import 'dart:io';

class DesktopLyricController {
  DesktopLyricController._() {
    stdin.transform(utf8.decoder).listen((event) {
      try {
        final Map messageMap = json.decode(event);
        print(messageMap);
      } catch (err, stack) {
        stderr.write(err);
        stderr.write(stack);
      }
    });
  }
}
'@

    New-ControllerFixture -Root $testRoot -Content $controller
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Path $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Protocol patch failed with exit code $LASTEXITCODE."
    }

    $patched = Get-Content -LiteralPath (Join-Path $testRoot 'lib\desktop_lyric_controller.dart') -Raw
    if ($patched -notmatch 'LineSplitter') {
        throw 'Patched controller does not use LineSplitter.'
    }
    if ($patched -match 'stdin\.transform\(utf8\.decoder\)\.listen') {
        throw 'Patched controller still parses raw stream chunks.'
    }

    $mismatchRoot = Join-Path $env:TEMP "coriander-desktop-lyric-protocol-mismatch-$([guid]::NewGuid().ToString('N'))"
    New-ControllerFixture -Root $mismatchRoot -Content 'void main() {}'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Path $mismatchRoot
    if ($LASTEXITCODE -eq 0) {
        throw 'Protocol patch unexpectedly accepted a mismatched controller.'
    }

    Write-Output 'Desktop lyric protocol patch tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
    if ($mismatchRoot -and (Test-Path -LiteralPath $mismatchRoot)) {
        Remove-Item -LiteralPath $mismatchRoot -Recurse -Force
    }
}
