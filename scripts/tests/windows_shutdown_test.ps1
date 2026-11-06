param([ValidateRange(1, 10)][int] $Repetitions = 3)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $repositoryRoot 'test\fixtures\windows_shutdown'
$work = Join-Path $repositoryRoot ('build\shutdown-probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $work 'data') -Force | Out-Null

$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
$flutterRoot = Split-Path (Split-Path $flutterCommand)
$engine = Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64'
$wrapper = Join-Path $engine 'cpp_client_wrapper'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$compiler = & $vswhere -all -products '*' -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\cl.exe' | Select-Object -First 1
if (-not $compiler) { throw 'Install the Visual C++ x64 build tools to run this native test.' }
$msvc = [IO.Directory]::GetParent((Split-Path $compiler)).Parent.Parent.FullName
$sdk = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots').KitsRoot10
$sdkVersion = Get-ChildItem -LiteralPath (Join-Path $sdk 'Lib') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'um\x64\kernel32.lib') } |
    Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
if (-not $sdkVersion) { throw 'Windows SDK x64 libraries are required.' }

Push-Location $repositoryRoot
try {
    & $flutterCommand build bundle --debug --no-pub --target-platform windows-x64 `
        --target (Join-Path $fixture 'main.dart') --asset-dir (Join-Path $work 'data\flutter_assets')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile the isolated Dart fixture.' }
} finally { Pop-Location }
Copy-Item -LiteralPath (Join-Path $engine 'flutter_windows.dll') -Destination $work
Copy-Item -LiteralPath (Join-Path $engine 'icudtl.dat') -Destination (Join-Path $work 'data')

$includeDirectories = @(
    "$msvc\include", "$sdk\Include\$sdkVersion\ucrt", "$sdk\Include\$sdkVersion\shared",
    "$sdk\Include\$sdkVersion\um", "$sdk\Include\$sdkVersion\winrt", $engine,
    "$wrapper\include", $fixture, "$repositoryRoot\windows\runner"
)
$sources = @(
    "$repositoryRoot\windows\runner\main.cpp", "$repositoryRoot\windows\runner\flutter_window.cpp",
    "$repositoryRoot\windows\runner\win32_window.cpp", "$repositoryRoot\windows\runner\utils.cpp",
    "$wrapper\core_implementations.cc", "$wrapper\standard_codec.cc",
    "$wrapper\flutter_engine.cc", "$wrapper\flutter_view_controller.cc", "$wrapper\plugin_registrar.cc",
    "$fixture\plugin_registrant.cpp"
)
$probe = Join-Path $work 'shutdown_probe.exe'
$compileArguments = @('/nologo', '/std:c++17', '/EHsc', '/MD', '/O2', '/DUNICODE', '/D_UNICODE', '/DNOMINMAX')
$compileArguments += $includeDirectories | ForEach-Object { '/I' + $_ }
$compileArguments += $sources
$compileArguments += @(('/Fe' + $probe), '/link', '/SUBSYSTEM:WINDOWS',
    ('/LIBPATH:' + $msvc + '\lib\x64'), ('/LIBPATH:' + $sdk + '\Lib\' + $sdkVersion + '\ucrt\x64'),
    ('/LIBPATH:' + $sdk + '\Lib\' + $sdkVersion + '\um\x64'), "$engine\flutter_windows.dll.lib",
    'kernel32.lib', 'user32.lib', 'gdi32.lib', 'shell32.lib', 'ole32.lib', 'advapi32.lib', 'dwmapi.lib')
Push-Location $work
try {
    & $compiler @compileArguments
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile the production Windows runner.' }
} finally { Pop-Location }

foreach ($mode in @('quit', 'close')) {
    for ($attempt = 1; $attempt -le $Repetitions; $attempt++) {
        $marker = Join-Path $work 'shutdown-requested.txt'
        if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
        $process = New-Object Diagnostics.Process
        $process.StartInfo.FileName = $probe
        $process.StartInfo.Arguments = $mode
        $process.StartInfo.WorkingDirectory = $work
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.WindowStyle = 'Hidden'
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            $process.Kill()
            throw "Owned test process timed out: $mode attempt $attempt"
        }
        $finished = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if ($process.ExitCode -ne 0) {
            throw "Native shutdown crashed: $mode attempt $attempt, exit code $($process.ExitCode). $($stderr.GetAwaiter().GetResult()) Artifacts: $work"
        }
        if (-not (Test-Path -LiteralPath $marker)) { throw 'Probe exited without requesting shutdown.' }
        $requested = [long](Get-Content -LiteralPath $marker -Raw)
        $elapsed = $finished - $requested
        if ($elapsed -gt 2000) { throw "Native shutdown took $elapsed ms: $mode attempt $attempt" }
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        $process.Dispose()
        Write-Output "windows_shutdown_test: $mode $attempt PASS ($elapsed ms; exit 0)"
    }
}
Write-Output "windows_shutdown_test: PASS; isolated artifacts: $work"
