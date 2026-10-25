# Smoke test of a packaged standalone timeline app (release workflow, job native-windows) - run it on an extracted
# portable ZIP or an installed copy, never on the folder that gets packaged (step B lets the app open the stores).
# ASCII only on purpose (see package-windows.ps1); Korean names come from <bundle>\bundle.json.
#
#   pwsh prototype/scripts/release/smoke-windows.ps1 -BundleDirectory <folder with Windows\ and bundle.json> [-CheckTools] [-SkipLaunch] [-LogDirectory <dir>]
#
# -SkipLaunch: skips A) and B) (the app is not started - for checking C) alone on a developer PC).
# A) plain launch (the default store through Windows\prototype.json): a visible window whose message loop answers,
#    still alive and answering after -AliveSeconds, then a normal close. It runs with --memory-dir=<logs>\memory (ruling R50):
#    the app keeps its view memory (ui-state.json) there instead of the user's %APPDATA%\local.archive\archive_prototype\
#    archive-prototype-v2 - a smoke run once overwrote that file on a real PC. The script fails if any file under the user's
#    local.archive\archive_prototype folders (%APPDATA% and %LOCALAPPDATA% - names, sizes and times only, never contents) is
#    created, changed or removed during the run, and waits up to -TimeoutSeconds for <logs>\memory\ui-state.json to appear
#    (the handle took effect - a slow runner may need more than -AliveSeconds).
# B) every store once in capture mode (--db=<store> --measure=<dir> --capture-only=yes --exit=yes - lib/measure/runner.dart):
#    the app opens the store with the real engine, draws the first scene, writes one PNG and one JSON and exits by itself.
#    This is the proof that archive_engine.dll and the store work; a window alone would also stay up on an error screen.
#    Capture mode never reads or writes the view memory; it gets --memory-dir as well so nothing asks for %APPDATA%.
# C) with -CheckTools: the bundled engine tool (archive-tool.exe) finds the calendar table (blobs key calendar:table) in every
#    store and checks the tiles - the engine refuses to add or remove DLC on a store without that table (ruling R36), and the
#    stores now come from archive-tool build (build-showcase.mjs). The bundle carries no Node.js any more (ruling R49).
#    It also reads the base pack original next to the tool (results\compat\east-asia.htpack - check-pack: id and version), and
#    runs the bundle's add and remove path once (ruling R58): on a copy of a store that does not hold that pack, add-pack it,
#    pack-out its original again (check-pack: same id and version - the app's seed carry and DLC folder copies use pack-out),
#    turn it off (remove-pack without --delete: the original stays in the store's shelf, kept_packs) and on (add-pack --ids),
#    remove-pack it with --delete, verify the tiles and check that the copy holds the same packs as before and an empty shelf.
#    Limit: C) runs the engine tool's command-line path. The app's own path (archive_engine.dll add_pack / remove_pack through
#    FFI) is the same engine code but is not driven here - B) only opens each store and draws its first scene.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDirectory,

    [ValidateRange(10, 900)]
    [int]$TimeoutSeconds = 180,

    [ValidateRange(1, 120)]
    [int]$AliveSeconds = 8,

    [switch]$CheckTools,

    [switch]$SkipLaunch,

    [string]$LogDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('ht-smoke-' + [guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Native tools print UTF-8; JSON arguments must reach them with their quotes (PowerShell 7.3+).
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$PSNativeCommandArgumentPassing = 'Standard'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This smoke test must run on Windows with an interactive desktop.' }
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$info = Get-Content -LiteralPath (Join-Path $bundle 'bundle.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$exe = Join-Path (Join-Path $bundle 'Windows') ([string]$info.exe)
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Packaged executable is missing: $exe" }
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$logs = (Resolve-Path -LiteralPath $LogDirectory).Path
Write-Host "Smoke test: $exe"
Write-Host "Logs: $logs"

if ($null -eq ('HtSmokeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HtSmokeNative {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
}

function Test-ResponsiveWindow {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    $Process.Refresh()
    if ($Process.HasExited) { return $false }
    $window = $Process.MainWindowHandle
    if ($window -eq [IntPtr]::Zero -or -not [HtSmokeNative]::IsWindowVisible($window)) { return $false }
    [uint32]$owner = 0
    [void][HtSmokeNative]::GetWindowThreadProcessId($window, [ref]$owner)
    if ($owner -ne $Process.Id) { return $false }
    [UIntPtr]$result = [UIntPtr]::Zero
    # WM_NULL with SMTO_BLOCK | SMTO_ABORTIFHUNG, 500 ms: the UI message loop must answer.
    return [HtSmokeNative]::SendMessageTimeout($window, 0, [UIntPtr]::Zero, [IntPtr]::Zero, 3, 500, [ref]$result) -ne [IntPtr]::Zero
}

function Stop-Started {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    $Process.Refresh()
    if (-not $Process.HasExited) {
        [void]$Process.CloseMainWindow()
        if (-not $Process.WaitForExit(5000)) {
            # Only the process this script started - never by name.
            $Process.Kill()
            [void]$Process.WaitForExit(5000)
        }
    }
}

function Show-Logs {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Write-Host "--- $path"
            Get-Content -LiteralPath $path -Tail 100 -Encoding UTF8 | ForEach-Object { Write-Host $_ }
        }
    }
}

$workDir = Split-Path -Parent $exe

if ($SkipLaunch) {
    Write-Host 'A) and B) skipped (-SkipLaunch) - the app was not started.'
} else {
    # The user's own app data (ruling R50) - only file names, sizes and times are looked at, never contents. The folder names come
    # from Runner.rc (CompanyName local.archive, ProductName archive_prototype) through path_provider and lib/ui/app_memory.dart.
    $userFolders = @(
        (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'local.archive\archive_prototype'),
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'local.archive\archive_prototype')
    )
    function Get-MemoryStamp {
        $stamp = foreach ($folder in $userFolders) {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { "$folder missing"; continue }
            "$folder present"
            Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
                '{0}|{1}|{2}' -f $_.FullName.Substring($folder.Length), $_.LastWriteTimeUtc.Ticks, $(if ($_.PSIsContainer) { 'dir' } else { $_.Length })
            }
        }
        return ($stamp -join "`n")
    }
    function Assert-UserMemoryUntouched {
        param([string]$Before, [string]$Step)
        $after = Get-MemoryStamp
        # (A copy of the app that the user runs at the same time would also change it - close it before a local smoke run.)
        if ($after -ne $Before) {
            $changed = @(Compare-Object -ReferenceObject ($Before -split "`n") -DifferenceObject ($after -split "`n") | ForEach-Object { '{0} {1}' -f $_.SideIndicator, $_.InputObject })
            throw "$Step touched the user's app data under local.archive\archive_prototype although the app ran with --memory-dir (ruling R50): $($changed -join '; ')"
        }
    }
    $memoryBefore = Get-MemoryStamp
    $memory = Join-Path $logs 'memory'
    New-Item -ItemType Directory -Force -Path $memory | Out-Null

    # A) Plain launch.
    $out = Join-Path $logs 'launch.stdout.log'
    $err = Join-Path $logs 'launch.stderr.log'
    $process = $null
    try {
        $process = Start-Process -FilePath $exe -ArgumentList @("--memory-dir=`"$memory`"") -WorkingDirectory $workDir -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        [void]$process.Handle  # keep the handle so ExitCode is still readable after the process exits
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-ResponsiveWindow -Process $process)) {
            if ($process.HasExited) { throw "The app exited before showing a window (exit code $($process.ExitCode))." }
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "No responsive window within $TimeoutSeconds s." }
            Start-Sleep -Milliseconds 250
        }
        $shown = $watch.Elapsed.TotalSeconds
        $silent = 0
        $alive = [Diagnostics.Stopwatch]::StartNew()
        while ($alive.Elapsed.TotalSeconds -lt $AliveSeconds) {
            $process.Refresh()
            if ($process.HasExited) { throw "The app exited $([int]$alive.Elapsed.TotalSeconds) s after its window appeared (exit code $($process.ExitCode))." }
            if (-not (Test-ResponsiveWindow -Process $process)) { $silent++ }
            Start-Sleep -Milliseconds 250
        }
        if (-not (Test-ResponsiveWindow -Process $process)) { throw "The window stopped answering after $AliveSeconds s." }
        if ($silent -gt 0) { Write-Warning "The window did not answer $silent time(s) during the $AliveSeconds s." }
        Write-Host ("A) window '{0}' after {1:N1} s, alive and answering for {2} s" -f $process.MainWindowTitle, $shown, $AliveSeconds)
        # The app saves its first view (400 ms batching after the view settles) - wait for it up to -TimeoutSeconds on a slow runner.
        $memoryFile = Join-Path $memory 'ui-state.json'
        $waited = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $memoryFile -PathType Leaf)) {
            $process.Refresh()
            if ($process.HasExited -or $waited.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $process.CloseMainWindow()) { throw 'The window did not accept a normal close request.' }
        if (-not $process.WaitForExit(15000)) { throw 'The app did not exit within 15 s of closing its window.' }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { Write-Warning "The app exited with code $($process.ExitCode) after a normal close." }
    } catch {
        Show-Logs -Paths @($out, $err)
        throw
    } finally {
        Stop-Started -Process $process
    }
    Assert-UserMemoryUntouched -Before $memoryBefore -Step 'A) plain launch'
    if (-not (Test-Path -LiteralPath (Join-Path $memory 'ui-state.json') -PathType Leaf)) { throw "A) the app did not write its view memory into $memory within $TimeoutSeconds s (it ignored --memory-dir, or the default store did not open)." }
    Write-Host "A) view memory kept in $memory (the user's own memory untouched)"

    # B) Each store once in capture mode.
    $index = 0
    foreach ($store in @($info.stores)) {
        $index++
        $db = Join-Path $bundle (([string]$store.db) -replace '/', '\')
        $dir = Join-Path $logs "capture-$index"
        $out = Join-Path $logs "capture-$index.stdout.log"
        $err = Join-Path $logs "capture-$index.stderr.log"
        $arguments = @("--db=`"$db`"", "--measure=`"$dir`"", '--capture-only=yes', '--exit=yes', "--memory-dir=`"$memory`"")
        $process = $null
        try {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $workDir -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
            [void]$process.Handle
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw "Store $index ($($store.db)) did not finish its capture within $TimeoutSeconds s." }
            $process.WaitForExit()
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Store $index ($($store.db)): the app exited (code $($process.ExitCode)) without starting the capture - the store did not open." }
            $failed = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.txt')
            if ($failed.Count -gt 0) { Show-Logs -Paths @($failed[0].FullName); throw "Store $index ($($store.db)): the capture failed." }
            $png = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.png')
            $json = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.json')
            if ($png.Count -ne 1 -or $json.Count -ne 1 -or $png[0].Length -lt 1000) { throw "Store $index ($($store.db)): expected one picture and one scene record in $dir." }
            $scene = Get-Content -LiteralPath $json[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $failures = @($scene.ask_failures)
            if ($failures.Count -gt 0) { Write-Warning "Store $index ($($store.db)): $($failures.Count) engine queries failed before the capture: $($failures[0])" }
            Copy-Item -LiteralPath $png[0].FullName -Destination (Join-Path $logs "capture-$index.png")
            Write-Host ("B) store {0} ({1}): first scene drawn and saved in {2:N1} s, exit code {3}" -f $index, $store.db, $watch.Elapsed.TotalSeconds, $process.ExitCode)
        } catch {
            Show-Logs -Paths @($out, $err)
            throw
        } finally {
            Stop-Started -Process $process
        }
    }
    Assert-UserMemoryUntouched -Before $memoryBefore -Step 'B) capture runs'
}

# C) The DLC tools that ship in the bundle.
if ($CheckTools) {
    $tool = @(Get-ChildItem -LiteralPath $bundle -Recurse -File -Filter 'archive-tool.exe')[0].FullName
    # The base pack original that the app's text for removing the base pack points at (<tools>\prototype\results\compat).
    $basePack = Join-Path (Split-Path -Parent $tool) 'results\compat\east-asia.htpack'
    if (-not (Test-Path -LiteralPath $basePack -PathType Leaf)) { throw "The base pack original is missing from the tools folder: $basePack" }
    $basePackJson = Join-Path $logs 'base-pack.json'
    & $tool check-pack $basePack $basePackJson
    if ($LASTEXITCODE -ne 0) { throw "The base pack original does not read as a DLC file: $basePack" }
    $basePackHead = Get-Content -LiteralPath $basePackJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $baseId = if ($basePackHead.PSObject.Properties['id']) { [string]$basePackHead.id } else { '' }
    $baseVersion = if ($basePackHead.PSObject.Properties['version']) { [string]$basePackHead.version } else { '' }
    if (-not $baseId -or -not $baseVersion) { throw "The base pack original has no id or version: $basePack" }
    Write-Host "C) base pack original: $basePack ($baseId v$baseVersion)"

    # The DLC ids of a store, in pack order (meta.pack_info of {"op":"info"}). PowerShell before 7.3 drops the inner quotes of a
    # native argument unless they are escaped (compare Major and Minor - pwsh's PSVersion is a SemanticVersion, not a [version]).
    $psVersion = $PSVersionTable.PSVersion
    $quotesKept = $psVersion.Major -gt 7 -or ($psVersion.Major -eq 7 -and $psVersion.Minor -ge 3)
    $infoQuery = if ($quotesKept) { '{"op":"info"}' } else { '{\"op\":\"info\"}' }
    function Get-StorePacks {
        param([string]$Db)
        $lines = @(& $tool query $Db $infoQuery | Where-Object { $_.Trim() })
        if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) { throw "query info failed on $Db" }
        $answer = $lines[-1] | ConvertFrom-Json
        $meta = if ($answer.PSObject.Properties['data']) { $answer.data.meta } else { $answer.meta }
        $packInfo = $meta.pack_info
        if ($packInfo -is [string]) { $packInfo = $packInfo | ConvertFrom-Json }
        return @($packInfo.PSObject.Properties | Sort-Object { [int]$_.Name } | ForEach-Object { [string]$_.Value.id })
    }
    # The DLC ids on the store's shelf (turned off, original kept - {"op":"kept_packs"}).
    $keptQuery = if ($quotesKept) { '{"op":"kept_packs"}' } else { '{\"op\":\"kept_packs\"}' }
    function Get-KeptPacks {
        param([string]$Db)
        $lines = @(& $tool query $Db $keptQuery | Where-Object { $_.Trim() })
        if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) { throw "query kept_packs failed on $Db" }
        $answer = $lines[-1] | ConvertFrom-Json
        if ($null -eq $answer) { return @() }
        $list = if ($answer -isnot [array] -and $answer.PSObject.Properties['data']) { $answer.data } else { $answer }
        return @(@($list) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.id })
    }
    # The add and remove path of the bundle (ruling R58) on a copy - the bundle's own stores stay as they are.
    $hostDb = $null
    foreach ($store in @($info.stores)) {
        $db = Join-Path $bundle (([string]$store.db) -replace '/', '\')
        if (@(Get-StorePacks -Db $db) -notcontains $baseId) { $hostDb = $db; break }
    }
    if ($null -eq $hostDb) {
        Write-Warning "C) every store already holds $baseId - the add and remove path was not run."
    } else {
        $copyDir = Join-Path $logs 'add-remove'
        New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
        $copy = Join-Path $copyDir 'archive.db'
        Copy-Item -LiteralPath $hostDb -Destination $copy
        $before = (Get-StorePacks -Db $copy) -join ','
        $watch = [Diagnostics.Stopwatch]::StartNew()
        & $tool add-pack $copy $basePack | Out-File -LiteralPath (Join-Path $logs 'add-pack.json') -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "add-pack of the base pack original failed on a copy of $hostDb ($LASTEXITCODE)" }
        if (@(Get-StorePacks -Db $copy) -notcontains $baseId) { throw "add-pack did not put $baseId into the copy of $hostDb" }
        # pack-out: the original comes back out of the store as a DLC file with the same id and version.
        $outPack = Join-Path $copyDir 'pack-out.htpack'
        & $tool pack-out $copy $baseId $outPack | Out-File -LiteralPath (Join-Path $logs 'pack-out.json') -Encoding utf8
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outPack -PathType Leaf)) { throw "pack-out of $baseId failed on the copy of $hostDb ($LASTEXITCODE)" }
        $outJson = Join-Path $copyDir 'pack-out-head.json'
        & $tool check-pack $outPack $outJson
        if ($LASTEXITCODE -ne 0) { throw "The pack-out file does not read as a DLC file: $outPack" }
        $outHead = Get-Content -LiteralPath $outJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$outHead.id -ne $baseId -or [string]$outHead.version -ne $baseVersion) { throw "pack-out gave $($outHead.id) v$($outHead.version), expected $baseId v$baseVersion" }
        # Off and on again, as the app's switch does: remove-pack without --delete keeps the original on the shelf, add-pack --ids takes it back.
        & $tool remove-pack $copy $baseId | Out-File -LiteralPath (Join-Path $logs 'off-pack.json') -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "remove-pack (off) of $baseId failed on the copy of $hostDb ($LASTEXITCODE)" }
        if (@(Get-StorePacks -Db $copy) -contains $baseId) { throw "remove-pack (off) left $baseId in the packs of the copy" }
        if (@(Get-KeptPacks -Db $copy) -notcontains $baseId) { throw "remove-pack (off) did not keep the original of $baseId on the shelf" }
        & $tool add-pack $copy "--ids=$baseId" | Out-File -LiteralPath (Join-Path $logs 'on-pack.json') -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "add-pack --ids=$baseId (on) failed on the copy of $hostDb ($LASTEXITCODE)" }
        if (@(Get-StorePacks -Db $copy) -notcontains $baseId) { throw "add-pack --ids did not turn $baseId back on" }
        & $tool remove-pack $copy $baseId --delete | Out-File -LiteralPath (Join-Path $logs 'remove-pack.json') -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "remove-pack --delete of $baseId failed on the copy of $hostDb ($LASTEXITCODE)" }
        & $tool verify-tiles $copy 120
        if ($LASTEXITCODE -ne 0) { throw "verify-tiles failed on the copy after add and remove: $LASTEXITCODE" }
        $after = (Get-StorePacks -Db $copy) -join ','
        if ($after -ne $before) { throw "The copy holds other packs after add and remove: [$before] -> [$after]" }
        $shelf = @(Get-KeptPacks -Db $copy)
        if ($shelf.Count -ne 0) { throw "The shelf of the copy is not empty after remove-pack --delete: [$($shelf -join ',')]" }
        Write-Host ("C) add-pack, pack-out, off, on, remove-pack --delete of {0} on a copy of {1}: {2:N1} s, tiles verified, packs back to [{3}], shelf empty" -f $baseId, $hostDb, $watch.Elapsed.TotalSeconds, $after)
    }
    $n = 0
    foreach ($store in @($info.stores)) {
        $db = Join-Path $bundle (([string]$store.db) -replace '/', '\')
        $table = Join-Path $logs ("calendar-table-{0}.zlib" -f $n)
        $n++
        & $tool blob $db 'calendar:table' $table
        if ($LASTEXITCODE -ne 0) { throw "The store has no calendar table (calendar:table) - the app could not add or remove DLC there: $($store.db)" }
        $size = (Get-Item -LiteralPath $table).Length
        if ($size -lt 1024) { throw "The calendar table of $($store.db) is too small: $size bytes" }
        & $tool verify-tiles $db 120
        if ($LASTEXITCODE -ne 0) { throw "verify-tiles failed on $($store.db): $LASTEXITCODE" }
        Write-Host ("C) {0}: calendar table {1:N0} bytes (zlib); tiles verified" -f $store.db, $size)
    }
}

Write-Host 'Smoke test passed.'
