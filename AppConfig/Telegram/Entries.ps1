$telegramPackageFamily = 'TelegramMessengerLLP.TelegramDesktop_t4vj0pshhgkwm'
$telegramTdataDirectory = Join-Path $env:LOCALAPPDATA "Packages\$telegramPackageFamily\LocalCache\Roaming\Telegram Desktop UWP\tdata"
$telegramSource = Join-Path $PSScriptRoot 'experimental_options.json'
$telegramDestination = Join-Path $telegramTdataDirectory 'experimental_options.json'
$telegramStartupKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$telegramPackageFamily\TelegramStartupTask"

InitWin-DefineEntry -Id App.Telegram.Config -Validate {
    $fileResult = InitWin-TestSingleFileDesired -Source $telegramSource -Destination $telegramDestination
    if ($fileResult.Status -ne 'Desired') { return $fileResult }

    if (-not (Test-Path $telegramStartupKey)) {
        return InitWin-NewValidationResult -Status Unset -Target "registry key: $telegramStartupKey" -Current '<missing>' -Expected 'present'
    }
    $state = (Get-ItemProperty -Path $telegramStartupKey -Name 'State' -ErrorAction SilentlyContinue).State
    if ($state -eq 2) { return InitWin-NewValidationResult -Status Desired }
    InitWin-NewValidationResult -Status Conflict -Target "registry: $telegramStartupKey\State" -Current $state -Expected 2
} -Apply {
    Get-Process -Name 'Telegram' -ErrorAction SilentlyContinue | Stop-Process -Force

    InitWin-CopyFile -Source $telegramSource -Destination $telegramDestination
    InitWin-WriteDetail 'experimental_options.json'

    if (-not (Test-Path $telegramStartupKey)) {
        InitWin-WriteDetail 'Telegram startup task key 不存在，跳过 autostart 设置 (Telegram 可能尚未启动过)' -ForegroundColor Yellow
    } else {
        Set-ItemProperty -Path $telegramStartupKey -Name 'State' -Value 2 -Type DWord
        Set-ItemProperty -Path $telegramStartupKey -Name 'UserEnabledStartupOnce' -Value 1 -Type DWord
        InitWin-WriteDetail 'startup task enabled'
    }
}
