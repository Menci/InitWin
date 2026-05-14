# Snipaste/Apply.ps1
# 1) 拷 config.ini 到 MSIX LocalState
# 2) 注册 \Snipaste (Run As Admin) @4D20 计划任务
#    Snipaste GUI 里的 "Run as administrator on boot" 才会建这个任务，
#    config.ini 的 as_admin=true 不会触发重建（issue #1545），所以脚本里硬编码。
#    参考一台已开启此选项的机器导出的 schtask XML。

$ErrorActionPreference = 'Stop'

$src   = Join-Path $PSScriptRoot 'config.ini'
$pkg   = '45479liulios.17062D84F7C46_p7pnf6hceqser'
$dst   = Join-Path $env:LOCALAPPDATA "Packages\$pkg\LocalState\config.ini"

Get-Process -Name 'Snipaste' -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
Copy-Item $src $dst -Force
Write-Host "  config.ini"

# 计划任务：trigger 为空（Snipaste 主进程拉起，不是 schtasks 自启动）；
# RunLevel=Highest 让 Snipaste.exe 以管理员身份启动。
$taskName = 'Snipaste (Run As Admin) @4D20'
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action    = New-ScheduledTaskAction -Execute '%LOCALAPPDATA%\Microsoft\WindowsApps\Snipaste.exe'
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType InteractiveToken -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -MultipleInstances Parallel `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -Priority 4 `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

$task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings `
    -Description 'Run Snipaste admin privileges.'

Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
Write-Host "  scheduled task: \$taskName"
