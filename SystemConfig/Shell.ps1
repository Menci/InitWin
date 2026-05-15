$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$multitaskingProperties = @(
    InitWin-NewRegistryProperty -Path $advanced -Name 'MultiTaskingAltTabFilter' -Type DWord -Value 3
    InitWin-NewRegistryProperty -Path $advanced -Name 'DisallowShaking' -Type DWord -Value 0
)

$explorerProperties = @(
    InitWin-NewRegistryProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $advanced -Name 'HideFileExt' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $advanced -Name 'Hidden' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $advanced -Name 'ShowSuperHidden' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $advanced -Name 'HideDrivesWithNoMedia' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Type DWord -Value 1
)

InitWin-DefineEntry -Id System.Shell.Multitasking -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $multitaskingProperties
} -Apply {
    InitWin-WriteStep '多任务 / Alt+Tab / Aero Shake'
    InitWin-SetRegistryProperties -Properties $multitaskingProperties
}

InitWin-DefineEntry -Id System.Shell.Explorer -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $explorerProperties
} -Apply {
    InitWin-WriteStep '高级 / 任务栏 / 文件管理器'
    InitWin-SetRegistryProperties -Properties $explorerProperties
}
