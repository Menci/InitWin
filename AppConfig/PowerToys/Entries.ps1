$powerToysSourceDirectory = $PSScriptRoot
$powerToysDestinationDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'

InitWin-DefineEntry -Id App.PowerToys.Config -Profiles @() -Validate {
    InitWin-TestDirectoryFilesDesired -SourceDirectory $powerToysSourceDirectory -DestinationDirectory $powerToysDestinationDirectory
} -Apply {
    Get-Process -Name 'PowerToys','PowerToys.Settings' -ErrorAction SilentlyContinue | Stop-Process -Force
    InitWin-CopyDirectoryFiles -SourceDirectory $powerToysSourceDirectory -DestinationDirectory $powerToysDestinationDirectory
}
