# Packages the standalone timeline app for Windows (release workflow, job native-windows).
# ASCII only on purpose - Windows PowerShell 5.1 reads a script without a BOM as ANSI. Every Korean name (app title,
# store labels and paths) is read from <bundle>\bundle.json (UTF-8), written by prototype/scripts/bundle-app.mjs.
#
#   pwsh prototype/scripts/release/package-windows.ps1 -Version 1.1.0 -BundleDirectory <bundle folder> [-OutputDirectory out/windows] [-PortableOnly]
#
# -PortableOnly: a light release (release.yml - not a major x.0.0 version) ships the portable ZIP only - step 4 skips
#   Inno Setup, so ISCC.exe is not needed. Steps 1-3 run the same.
#
# 1) checks the bundle (Flutter runtime, archive_engine.dll, prototype.json, every store, the engine tool archive-tool.exe and the
#    base pack original east-asia.htpack next to it),
# 2) adds the MSVC runtime DLLs next to the app and next to archive-tool.exe when Flutter/Rust did not ship them
#    (a clean PC without the VC++ redistributable must still start both),
# 3) checks that the EXE version matches the release version (pubspec.yaml version = package.json version),
# 4) makes HistoryTimeline-<v>-windows-x64-portable.zip (one top folder = the bundle folder) and, unless -PortableOnly,
#    HistoryTimeline-<v>-windows-x64-setup.exe (Inno Setup 6, per-user install, installer.iss next to this script).
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$BundleDirectory,

    [string]$OutputDirectory = 'out/windows',

    [switch]$PortableOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$info = Get-Content -LiteralPath (Join-Path $bundle 'bundle.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($info.kind -ne 'history-timeline-bundle') { throw 'bundle.json is not a history-timeline bundle.' }
if ([string]$info.version -ne $Version) { throw "Bundle version $($info.version) does not match the release version $Version." }
$exeName = [string]$info.exe
$app = Join-Path $bundle 'Windows'

# 1) The bundle.
foreach ($file in @($exeName, 'flutter_windows.dll', 'archive_engine.dll', 'prototype.json', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets/AssetManifest.bin')) {
    if (-not (Test-Path -LiteralPath (Join-Path $app $file) -PathType Leaf)) { throw "Incomplete Windows bundle: Windows/$file" }
}
foreach ($store in @($info.stores)) {
    $db = Join-Path $bundle (([string]$store.db) -replace '/', '\')
    if (-not (Test-Path -LiteralPath $db -PathType Leaf)) { throw "Store is missing from the bundle: $($store.db)" }
}
$default = @($info.stores | Where-Object { $_.default })
if ($default.Count -ne 1) { throw 'bundle.json must name exactly one default store.' }
# The tools folder carries the engine tool only (no Node.js, no add-dlc.mjs since plan P4 task 11 / ruling R49): the app adds and
# removes DLC through archive_engine.dll and uses archive-tool.exe to read DLC files when it carries DLC over after an upgrade.
$tools = @{}
foreach ($name in @('archive-tool.exe')) {
    $found = @(Get-ChildItem -LiteralPath $bundle -Recurse -File -Filter $name)
    if ($found.Count -ne 1) { throw "The DLC tools are incomplete: expected one $name, found $($found.Count)." }
    $tools[$name] = $found[0].FullName
}
# The base pack original next to it (<tools>\prototype\results\compat\east-asia.htpack - bundle-app.mjs): the app's text for removing
# the base pack points at this file as the way to bring it back.
$basePack = Join-Path (Split-Path -Parent $tools['archive-tool.exe']) 'results\compat\east-asia.htpack'
if (-not (Test-Path -LiteralPath $basePack -PathType Leaf)) { throw "The base pack original is missing from the tools folder: $basePack" }

# 2) MSVC runtime (app-local copies of the redistributable DLLs).
$system = [Environment]::SystemDirectory
foreach ($folder in @($app, (Split-Path -Parent $tools['archive-tool.exe']))) {
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        $target = Join-Path $folder $dll
        if (Test-Path -LiteralPath $target -PathType Leaf) { continue }
        $source = Join-Path $system $dll
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "MSVC runtime $dll is neither in $folder nor in $system." }
        Copy-Item -LiteralPath $source -Destination $target
        Write-Host "Added $dll to $folder (from $system)"
    }
}

# 3) The EXE carries the pubspec.yaml version (Flutter writes it into the VERSIONINFO resource).
$exeInfo = (Get-Item -LiteralPath (Join-Path $app $exeName)).VersionInfo
if ($exeInfo.ProductVersion -notmatch "^$([regex]::Escape($Version))(\+|\.|$)") {
    throw "EXE version '$($exeInfo.ProductVersion)' does not match the release version $Version - raise prototype/app/pubspec.yaml together with package.json."
}

# 4) Portable ZIP and (unless -PortableOnly) the installer.
$portable = Join-Path $output "HistoryTimeline-$Version-windows-x64-portable.zip"
$installer = Join-Path $output "HistoryTimeline-$Version-windows-x64-setup.exe"
if ((Test-Path -LiteralPath $portable) -or (Test-Path -LiteralPath $installer)) { throw "Output already exists in $output - use an empty folder." }

Add-Type -AssemblyName System.IO.Compression.FileSystem
# UTF-8 entry names (the stores and the tools have Hangul names); includeBaseDirectory keeps one top folder.
[IO.Compression.ZipFile]::CreateFromDirectory($bundle, $portable, [IO.Compression.CompressionLevel]::Optimal, $true, [Text.Encoding]::UTF8)

$made = @($portable)
if (-not $PortableOnly) {
    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $compiler = if ($iscc) { $iscc.Source } else { Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Inno Setup 6 (ISCC.exe) is required to make the installer.' }
    $defines = @("/DAppVersion=$Version", "/DSourceDir=$bundle", "/DOutputDir=$output", "/DExeName=$exeName", "/DAppTitle=$($info.title)")
    if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $compiler) 'Languages\Korean.isl'))) {
        Write-Warning 'This Inno Setup has no Languages\Korean.isl - the installer wizard will be English only.'
        $defines += '/DNoKorean'
    }
    # The tools' results folder (<tools>\prototype\results - the base pack east-asia.htpack) - removed on install so an upgrade never keeps an old base pack.
    $toolsRoot = Split-Path -Parent $tools['archive-tool.exe']
    $defines += "/DToolResults=$((Join-Path $toolsRoot 'results').Substring($bundle.Length).TrimStart('\', '/'))"
    # The tools folder itself (<tools> - the parent of prototype\archive-tool.exe): an upgrade removes what older versions kept there
    # (node, js, packs, prototype\scripts, index.html) and the old DLC-*.cmd in the bundle root - see [InstallDelete] in installer.iss.
    # Never pass an empty value: {app}\{#ToolsDir}\js would then name the install root's own folders.
    $toolsDir = (Split-Path -Parent $toolsRoot).Substring($bundle.Length).TrimStart('\', '/')
    if ($toolsDir) {
        $defines += "/DToolsDir=$toolsDir"
    } else {
        Write-Warning "archive-tool.exe is not under a tools folder (<bundle>\<tools>\prototype) - the installer will not remove old tool files on upgrade."
    }
    # Every store path (Store1Db = the default store): an upgrade removes the store's old SQLite side files (-journal, -wal, -shm).
    # Since plan P4 the app rewrites the store in place; if it died while writing, a hot archive.db-journal stays behind, and the
    # engine would roll that old journal back into the new version's archive.db on the next open - see [InstallDelete].
    $defines += "/DStore1Db=$(([string]$default[0].db) -replace '/', '\')"
    $n = 2
    foreach ($store in @($info.stores | Where-Object { -not $_.default })) {
        if ($n -gt 4) { Write-Warning "installer.iss knows four stores only - no shortcut and no side-file cleanup for $($store.db)."; break }
        $defines += "/DStore${n}Label=$($store.label)"
        $defines += "/DStore${n}Db=$(([string]$store.db) -replace '/', '\')"
        $n++
    }
    & $compiler @defines (Join-Path $PSScriptRoot 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "The installer was not created: $installer" }
    $made = @($installer, $portable)
}

foreach ($file in $made) {
    $item = Get-Item -LiteralPath $file
    Write-Host ('{0}  {1:N1} MiB  {2}' -f $item.Name, ($item.Length / 1MB), (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant())
}
