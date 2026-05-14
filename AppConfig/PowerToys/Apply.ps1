# PowerToys/Apply.ps1
# 把同目录下的配置文件覆盖到 %LocalAppData%\Microsoft\PowerToys\
# 必须先关掉 PowerToys runner 和 Settings UI，否则会被进程内存覆写。
# 重启后 runner 读 settings.json 中的 startup=true 会自动重建 \PowerToys\Autorun for <user>
# 计划任务（src/runner/general_settings.cpp::apply_general_settings）。

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'

Get-Process -Name 'PowerToys','PowerToys.Settings' -ErrorAction SilentlyContinue | Stop-Process -Force

Get-ChildItem -Path $src -Recurse -File | Where-Object { $_.Name -ne 'Apply.ps1' } | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1)
    $target = Join-Path $dst $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item $_.FullName $target -Force
    Write-Host "  $rel"
}
