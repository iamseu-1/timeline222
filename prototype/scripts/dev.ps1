# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 script as ANSI and garbles Korean text.
# Usage: powershell -File prototype\scripts\dev.ps1 <engine-test|engine-build|app-get|app-check|app-build>
# Everything runs through an ASCII junction under %TEMP% (default ht-next-engine) because Flutter and MSBuild break on the Korean worktree path.
# -Junction <name>: use %TEMP%\<name> instead, so several worktrees can build at the same time (one junction per worktree).
# engine-test writes its scratch stores (archive-*) to %TMP%. Big runs can fill C:, so point TMP at a roomy drive first,
#   e.g. $env:TMP='D:\tmp-p34' (the junction stays under %TEMP%). The tests sweep stale archive-* left by finished runs.
param(
    [Parameter(Mandatory=$true)][ValidateSet('engine-test','engine-build','app-get','app-check','app-build')][string]$Task,
    [string]$Flutter = "$env:TEMP\ht-archive-flutter\flutter\bin\flutter.bat",
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Junction = 'ht-next-engine',
    # app-check only: run without the engine DLL on purpose. Without this switch app-check fails when engine\target\release\archive_engine.dll
    # is missing, because the real-engine test groups (contract_real_engine_test and friends) would otherwise skip silently (appfix review 3 Minor 8).
    [switch]$NoEngine
)
$ErrorActionPreference = 'Stop'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CARGO_TERM_COLOR = 'never'
$here = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$link = (Join-Path $env:TEMP $Junction).TrimEnd('\')
$item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
if ($here -ieq $link) {
    if (-not $item) { throw "junction $link is missing" }
} elseif (-not $item) {
    New-Item -ItemType Junction -Path $link -Target $here | Out-Null
} elseif (([string]$item.Target[0]).TrimEnd('\') -ine $here) {
    throw "junction $link points to $($item.Target[0]); expected $here. Remove it first if this worktree should own it."
}
$root = $link
$dart = Join-Path ([IO.Path]::GetDirectoryName($Flutter)) 'dart.bat'
# Only the app tasks need Flutter (engine-test / engine-build also run on a PC without it).
if ($Task -like 'app-*' -and -not (Test-Path -LiteralPath $Flutter)) { throw "Flutter SDK not found: $Flutter" }

function Assert-Exit([string]$what) { if ($LASTEXITCODE -ne 0) { throw "$what failed with exit code $LASTEXITCODE" } }

function Add-PluginLinks {
    # Same trick as build-windows.ps1: plugin junctions inside the project, no Developer Mode needed.
    $deps = Join-Path $root 'app\.flutter-plugins-dependencies'
    if (-not (Test-Path -LiteralPath $deps)) { return }
    $plugins = Get-Content -LiteralPath $deps -Raw | ConvertFrom-Json
    $links = Join-Path $root 'app\windows\flutter\ephemeral\.plugin_symlinks'
    New-Item -ItemType Directory -Path $links -Force | Out-Null
    foreach ($plugin in $plugins.plugins.windows) {
        $target = Join-Path $links $plugin.name
        if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Junction -Path $target -Target $plugin.path | Out-Null }
    }
}

function Add-EmptySeed {
    # pubspec.yaml lists assets/seed/ (Android first-run data). A Windows build only needs the folders to exist.
    $seed = Join-Path $root 'app\assets\seed'
    New-Item -ItemType Directory -Path (Join-Path $seed 'originals') -Force | Out-Null
    $manifest = Join-Path $seed 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifest)) { [IO.File]::WriteAllText($manifest, "[]`n", (New-Object Text.UTF8Encoding $false)) }
}

switch ($Task) {
    'engine-test' {
        Write-Host "test scratch: $([IO.Path]::GetTempPath())"
        cargo test --locked --release --manifest-path "$root\engine\Cargo.toml"
        Assert-Exit 'cargo test'
    }
    'engine-build' {
        cargo build --locked --release --manifest-path "$root\engine\Cargo.toml"
        Assert-Exit 'cargo build'
    }
    'app-get' {
        Add-EmptySeed
        Push-Location (Join-Path $root 'app')
        try {
            & $Flutter pub get
            if ($LASTEXITCODE -ne 0) {
                # First run without Developer Mode stops at the plugin symlink step: make junctions, then finish offline.
                Add-PluginLinks
                & $Flutter pub get --offline
                Assert-Exit 'flutter pub get --offline'
            }
        } finally { Pop-Location }
    }
    'app-check' {
        if (-not $NoEngine -and -not (Test-Path -LiteralPath "$root\engine\target\release\archive_engine.dll")) {
            throw 'engine DLL missing: the real-engine test groups would skip silently. Run dev.ps1 engine-build first, or pass -NoEngine to skip them on purpose.'
        }
        if ($NoEngine) { Write-Host 'app-check -NoEngine: the real-engine test groups may skip (engine DLL not required).' }
        Push-Location (Join-Path $root 'app')
        try {
            & $dart analyze --fatal-infos lib test
            Assert-Exit 'dart analyze'
            & $Flutter test --no-pub
            Assert-Exit 'flutter test'
        } finally { Pop-Location }
    }
    'app-build' {
        Add-EmptySeed
        Add-PluginLinks
        if (-not (Test-Path -LiteralPath "$root\engine\target\release\archive_engine.dll")) { throw 'build the engine first: dev.ps1 engine-build' }
        Push-Location (Join-Path $root 'app')
        try {
            # MSB8029 (build output under TEMP) repeats on stderr for every project: expected with the junction, so keep it out of the log.
            # Redirecting a native command's stderr under ErrorActionPreference=Stop throws in PowerShell 5.1, so relax it for this call only.
            $ErrorActionPreference = 'Continue'
            & $Flutter build windows --release --no-pub 2>$null
            $code = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($code -ne 0) { throw "flutter build windows failed with exit code $code (run it without dev.ps1 to see stderr)" }
        } finally { Pop-Location }
    }
}
Write-Output "done: $Task"
