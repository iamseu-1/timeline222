# ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less UTF-8 script as ANSI and garbles Korean text.
# Runs one program, waits for it, and writes {exit, timeout, wall_ms, cpu_ms, peak_ws_bytes, peak_commit_bytes} as JSON.
# Used by measure-addpack.mjs (prototype/scripts) to get the Windows PEAK WORKING SET of a child process, which Node cannot read.
# The peak comes from GetProcessMemoryInfo on the process handle we still hold after exit, so no polling can miss it.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File peak-run.ps1 -Request <request.json>
#   request.json (UTF-8): { "exe": "...", "args": ["...", ...], "stdout": "<file>", "stderr": "<file>", "cwd": "<dir or empty>",
#                           "result": "<file>", "timeout_ms": <int, optional: kill the child after this long> }
# Everything is passed by file, so Korean paths and quotes in the arguments never go through the PowerShell command line.
param([Parameter(Mandatory = $true)][string]$Request)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class PeakMem {
  [StructLayout(LayoutKind.Sequential, Size = 72)]
  public struct Counters {
    public uint cb; public uint PageFaultCount; public UIntPtr PeakWorkingSetSize; public UIntPtr WorkingSetSize;
    public UIntPtr QuotaPeakPagedPoolUsage; public UIntPtr QuotaPagedPoolUsage; public UIntPtr QuotaPeakNonPagedPoolUsage;
    public UIntPtr QuotaNonPagedPoolUsage; public UIntPtr PagefileUsage; public UIntPtr PeakPagefileUsage;
  }
  [DllImport("psapi.dll", SetLastError = true)] public static extern bool GetProcessMemoryInfo(IntPtr h, out Counters c, uint cb);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetProcessTimes(IntPtr h, out long created, out long exited, out long kernel, out long user);
}
"@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JobCap {
  [StructLayout(LayoutKind.Sequential)] public struct Basic { public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
  [StructLayout(LayoutKind.Sequential)] public struct Io { public ulong A, B, C, D, E, F; }
  [StructLayout(LayoutKind.Sequential)] public struct Ext { public Basic BasicLimits; public Io IoInfo; public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed; }
  [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr CreateJobObject(IntPtr attributes, string name);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref Ext info, int length);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  public static IntPtr Make(ulong memoryLimit) {
    IntPtr job = CreateJobObject(IntPtr.Zero, null);
    Ext info = new Ext();
    info.BasicLimits.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
    if (memoryLimit > 0) { info.BasicLimits.LimitFlags |= 0x100; info.ProcessMemoryLimit = new UIntPtr(memoryLimit); } // PROCESS_MEMORY
    SetInformationJobObject(job, 9, ref info, Marshal.SizeOf(typeof(Ext)));
    return job;
  }
}
"@

function Quote([string]$s) {
    # CommandLineToArgvW rules: wrap in quotes, double the backslashes before a quote, escape the quotes.
    if ($s -ne '' -and $s -notmatch '[\s"]') { return $s }
    $out = '"'
    $slashes = 0
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') { $slashes++; continue }
        if ($ch -eq '"') { $out += ('\' * ($slashes * 2 + 1)) + '"'; $slashes = 0; continue }
        $out += ('\' * $slashes) + $ch
        $slashes = 0
    }
    $out += ('\' * ($slashes * 2)) + '"'
    return $out
}

$req = [IO.File]::ReadAllText($Request, [Text.Encoding]::UTF8) | ConvertFrom-Json
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = [string]$req.exe
$psi.Arguments = (@($req.args) | ForEach-Object { Quote ([string]$_) }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [Text.Encoding]::UTF8
if ($req.cwd) { $psi.WorkingDirectory = [string]$req.cwd }
$timeout = -1
if ($req.timeout_ms) { $timeout = [int]$req.timeout_ms }

$start = [Diagnostics.Stopwatch]::StartNew()
$p = [Diagnostics.Process]::Start($psi)
$handle = $p.Handle
$limit = [uint64]0
if ($req.mem_limit_bytes) { $limit = [uint64]$req.mem_limit_bytes }
$job = [JobCap]::Make($limit)
[void][JobCap]::AssignProcessToJobObject($job, $handle)
# Read both pipes on other threads so a full pipe never stalls the child.
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
$finished = $p.WaitForExit($timeout)
if (-not $finished) { $p.Kill(); $p.WaitForExit() }
$start.Stop()
$outText = $outTask.Result
$errText = $errTask.Result

$c = New-Object PeakMem+Counters
$c.cb = [uint32][Runtime.InteropServices.Marshal]::SizeOf($c)
$ok = [PeakMem]::GetProcessMemoryInfo($handle, [ref]$c, $c.cb)
$cpu = $null
$t1 = [int64]0; $t2 = [int64]0; $tk = [int64]0; $tu = [int64]0
if ([PeakMem]::GetProcessTimes($handle, [ref]$t1, [ref]$t2, [ref]$tk, [ref]$tu)) { $cpu = [math]::Round(($tk + $tu) / 10000.0, 0) }

$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText([string]$req.stdout, $outText, $utf8)
[IO.File]::WriteAllText([string]$req.stderr, $errText, $utf8)
$result = [ordered]@{
    exit = $p.ExitCode
    timeout = (-not $finished)
    wall_ms = [math]::Round($start.Elapsed.TotalMilliseconds, 1)
    cpu_ms = $cpu
    peak_ws_bytes = $(if ($ok) { $c.PeakWorkingSetSize.ToUInt64() } else { $null })
    peak_commit_bytes = $(if ($ok) { $c.PeakPagefileUsage.ToUInt64() } else { $null })
}
[IO.File]::WriteAllText([string]$req.result, ($result | ConvertTo-Json -Compress), $utf8)
exit 0
