# Telegram/Apply.ps1
# Telegram Desktop 的大部分 GUI 偏好（主题、字体、标题栏边框等）都加密在
# tdata/settingss 里，且是按位置序列化的二进制 blob，写起来需要跟随 tdesktop 版本的
# 字段顺序。本轮先不处理 settingss，下一轮重构时配合 InitWin-* 库做编解码。
#
# 这里只处理 3 件事：
# 1) experimental_options.json (明文)
# 2) MSIX startup task: 等同于 Settings → Apps → Startup 里的 Telegram toggle
# 3) tdata/settingss 由用户手动迁移（如果需要保留主题等偏好）

$ErrorActionPreference = 'Stop'

$pkg = 'TelegramMessengerLLP.TelegramDesktop_t4vj0pshhgkwm'
$tdataDir = Join-Path $env:LOCALAPPDATA "Packages\$pkg\LocalCache\Roaming\Telegram Desktop UWP\tdata"

Get-Process -Name 'Telegram' -ErrorAction SilentlyContinue | Stop-Process -Force

# 1. experimental_options.json
New-Item -ItemType Directory -Force -Path $tdataDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'experimental_options.json') (Join-Path $tdataDir 'experimental_options.json') -Force
Write-Host "  experimental_options.json"

# 2. Startup task: State = 2 等同 Settings 里手动开 toggle
$startupKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$pkg\TelegramStartupTask"
if (-not (Test-Path $startupKey)) {
    Write-Warning "Telegram startup task key 不存在，跳过 autostart 设置 (Telegram 可能尚未启动过)"
} else {
    Set-ItemProperty -Path $startupKey -Name 'State' -Value 2 -Type DWord
    Set-ItemProperty -Path $startupKey -Name 'UserEnabledStartupOnce' -Value 1 -Type DWord
    Write-Host "  startup task enabled"
}
