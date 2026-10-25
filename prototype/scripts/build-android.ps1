# Android build of the archive app (stage 3 port). ASCII only - Windows PowerShell 5.1 reads scripts without a BOM as ANSI.
# Run it through the ASCII junction so that cargo / clang never see the Korean project path:
#   powershell -NoProfile -ExecutionPolicy Bypass -File %TEMP%\ht-next-engine\scripts\build-android.ps1
# What it does: 1) builds the Rust engine (.so) for each ABI with the NDK, 2) copies the Flutter sources to an ASCII temp folder
# (Gradle resolves junctions back to the Korean path, so a real copy is needed), 3) puts the bundled database into assets/seed of the COPY only
# (the app places it into its private folder on first run - lib/archive_app.dart _placeSeed), 4) builds one APK holding all ABIs.
# -Db   : database to bundle (default data\east-asia1\archive.db - the director's rule: real features are shown with the East Asia DLC)
# -Abis : arm64 = phones, x64 = emulator (default both)
param(
    [string]$Flutter = "$env:TEMP\ht-archive-flutter\flutter\bin\flutter.bat",
    [string]$Db = '',
    [string]$Abis = 'arm64,x64',
    [string]$Copy = "$env:TEMP\ht-archive-android-20260920"
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Db) { $Db = Join-Path $taskRoot 'data\east-asia1\archive.db' }
if (-not (Test-Path -LiteralPath $Db)) { throw "database not found: $Db" }
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$ndk = Join-Path $sdk 'ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin'
$table = @{
    'arm64' = @{ triple = 'aarch64-linux-android'; clang = 'aarch64-linux-android24-clang.cmd'; jni = 'arm64-v8a'; flutter = 'android-arm64' }
    'x64'   = @{ triple = 'x86_64-linux-android'; clang = 'x86_64-linux-android24-clang.cmd'; jni = 'x86_64'; flutter = 'android-x64' }
}
$env:ANDROID_HOME = $sdk
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$platforms = @()
Push-Location $taskRoot
try {
    foreach ($abi in $Abis.Split(',')) {
        $one = $table[$abi.Trim()]
        if (-not $one) { throw "unknown abi: $abi" }
        $under = $one.triple.Replace('-', '_')
        $clang = Join-Path $ndk $one.clang
        Set-Item -Path "env:CC_$under" -Value $clang
        Set-Item -Path "env:AR_$under" -Value (Join-Path $ndk 'llvm-ar.exe')
        Set-Item -Path ("env:CARGO_TARGET_" + $under.ToUpper() + "_LINKER") -Value $clang
        cargo build --locked --manifest-path engine/Cargo.toml --release --lib --target $one.triple
        if ($LASTEXITCODE -ne 0) { throw "engine build failed: $abi" }
        $libs = Join-Path $taskRoot ("app\android\app\src\main\jniLibs\" + $one.jni)
        New-Item -ItemType Directory -Path $libs -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $taskRoot ("engine\target\" + $one.triple + "\release\libarchive_engine.so")) -Destination (Join-Path $libs 'libarchive_engine.so') -Force
        $platforms += $one.flutter
    }
    New-Item -ItemType Directory -Path $Copy -Force | Out-Null
    # lib / assets are mirrored (stale files from older stages must not linger); android keeps its own build caches.
    foreach ($folder in @('lib', 'assets')) {
        & robocopy (Join-Path $taskRoot "app\$folder") (Join-Path $Copy $folder) /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -gt 7) { throw "copy failed: $folder" }
    }
    & robocopy (Join-Path $taskRoot 'app\android') (Join-Path $Copy 'android') /E /XD build .gradle .dart_tool /XF local.properties /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw 'copy failed: android' }
    foreach ($file in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')) {
        Copy-Item -LiteralPath (Join-Path $taskRoot "app\$file") -Destination (Join-Path $Copy $file) -Force
    }
    # bundled database: only inside the copy, so the Windows build never carries it.
    $seed = Join-Path $Copy 'assets\seed'
    New-Item -ItemType Directory -Path (Join-Path $seed 'originals') -Force | Out-Null
    Copy-Item -LiteralPath $Db -Destination (Join-Path $seed 'archive.db') -Force
    $file = Get-Item -LiteralPath $Db
    $stamp = [string]$file.Length + '-' + [string]$file.LastWriteTimeUtc.Ticks
    [IO.File]::WriteAllText((Join-Path $seed 'seed.json'), '{"database":"archive.db","stamp":"' + $stamp + '"}')
    if (-not (Test-Path -LiteralPath (Join-Path $seed 'manifest.json'))) { [IO.File]::WriteAllText((Join-Path $seed 'manifest.json'), '[]') }
    Set-Location $Copy
    & $Flutter pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'pub get failed' }
    & $Flutter build apk --release --target-platform ($platforms -join ',') --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'apk build failed' }
    $apk = Join-Path $Copy 'build\app\outputs\flutter-apk\app-release.apk'
    $out = Join-Path $taskRoot 'results\android'
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    Copy-Item -LiteralPath $apk -Destination (Join-Path $out 'archive-app.apk') -Force
    Write-Output ('APK: ' + (Join-Path $out 'archive-app.apk') + ' seed=' + $stamp)
} finally { Pop-Location }
