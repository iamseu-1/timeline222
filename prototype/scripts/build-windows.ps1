param([string]$Flutter = "$env:TEMP\ht-archive-flutter\flutter\bin\flutter.bat")
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
Push-Location (Join-Path $taskRoot 'app')
try {
    # 시스템 설정을 바꾸지 않고 이 작업 폴더에만 기존 플러그인 연결을 만든다.
    if (Test-Path -LiteralPath '.flutter-plugins-dependencies') {
        $plugins = Get-Content -LiteralPath '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
        $links = Join-Path (Get-Location) 'windows\flutter\ephemeral\.plugin_symlinks'
        New-Item -ItemType Directory -Path $links -Force | Out-Null
        foreach ($plugin in $plugins.plugins.windows) {
            $link = Join-Path $links $plugin.name
            if (-not (Test-Path -LiteralPath $link)) { New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null }
        }
    }
    & $Flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Windows 시제품 빌드 실패' }
} finally { Pop-Location }
