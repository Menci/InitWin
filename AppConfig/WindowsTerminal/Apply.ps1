# WindowsTerminal/Apply.ps1
# 把 settings.json 覆盖到 MSIX LocalState。
# WT 进程运行时改 settings.json 是安全的（它会监听文件变化重新加载），
# 但为了避免在加载半途被覆盖，先关掉所有窗口。

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'settings.json'
$pkg = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'
$dst = Join-Path $env:LOCALAPPDATA "Packages\$pkg\LocalState\settings.json"

Get-Process -Name 'WindowsTerminal','wt' -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
Copy-Item $src $dst -Force
Write-Host "  settings.json"
