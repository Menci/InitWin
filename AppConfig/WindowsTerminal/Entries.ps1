$windowsTerminalSource = Join-Path $PSScriptRoot 'settings.json'
$windowsTerminalPackageFamily = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'
$windowsTerminalDestination = Join-Path $env:LOCALAPPDATA "Packages\$windowsTerminalPackageFamily\LocalState\settings.json"

InitWin-DefineEntry -Id App.WindowsTerminal.Config -Profiles @() -Validate {
    InitWin-TestSingleFileDesired -Source $windowsTerminalSource -Destination $windowsTerminalDestination
} -Apply {
    Get-Process -Name 'WindowsTerminal','wt' -ErrorAction SilentlyContinue | Stop-Process -Force
    InitWin-CopyFile -Source $windowsTerminalSource -Destination $windowsTerminalDestination
    InitWin-WriteDetail 'settings.json'
}
