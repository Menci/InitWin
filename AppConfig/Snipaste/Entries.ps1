$snipasteSource = Join-Path $PSScriptRoot 'config.ini'
$snipastePackageFamily = '45479liulios.17062D84F7C46_p7pnf6hceqser'
$snipasteDestination = Join-Path $env:LOCALAPPDATA "Packages\$snipastePackageFamily\LocalState\config.ini"

InitWin-DefineEntry -Id App.Snipaste.Config -Validate {
    InitWin-TestSingleFileDesired -Source $snipasteSource -Destination $snipasteDestination
} -Apply {
    Get-Process -Name 'Snipaste' -ErrorAction SilentlyContinue | Stop-Process -Force
    InitWin-CopyFile -Source $snipasteSource -Destination $snipasteDestination
    InitWin-WriteDetail 'config.ini'

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
    InitWin-WriteDetail "scheduled task: $taskName"
}
