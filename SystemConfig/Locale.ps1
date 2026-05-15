$dateTimeProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name 'Start' -Type DWord -Value 4
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name 'Type' -Type String -Value 'NTP'
)

$regionalFormatProperties = @(
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\International' -Name 'iFirstDayOfWeek' -Type String -Value '0'
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\International' -Name 'sShortDate' -Type String -Value 'yyyy-MM-dd'
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\International' -Name 'sLongDate' -Type String -Value 'dddd, MMMM d, yyyy'
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\International' -Name 'sShortTime' -Type String -Value 'HH:mm'
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\International' -Name 'sTimeFormat' -Type String -Value 'HH:mm:ss'
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\International' -Name 'iMeasure' -Type String -Value '0'
)

$unicodeLocaleProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name 'ACP' -Type String -Value '65001'
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name 'OEMCP' -Type String -Value '65001'
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name 'MACCP' -Type String -Value '65001'
)

InitWin-DefineEntry -Id System.Locale.DateTime -Name '日期 / 时区' -Profiles @() -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    if ((Get-TimeZone).Id -ne 'China Standard Time') {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target 'time zone' -Current (Get-TimeZone).Id -Expected 'China Standard Time'))
    }

    foreach ($registryResult in @(InitWin-TestRegistryPropertiesDesired -Properties $dateTimeProperties)) {
        if ($registryResult.Status -ne 'Desired') { $results.Add($registryResult) }
    }

    $timeService = Get-Service -Name w32time
    if ($timeService.StartType -ne 'Automatic') {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target 'service: w32time StartType' -Current $timeService.StartType -Expected 'Automatic'))
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    Set-TimeZone -Id 'China Standard Time'
    InitWin-SetRegistryProperties -Properties $dateTimeProperties
    Set-Service -Name w32time -StartupType Automatic
    Start-Service -Name w32time -ErrorAction SilentlyContinue
    InitWin-InvokeNative -FilePath w32tm -Arguments @('/resync', '/force')
}

InitWin-DefineEntry -Id System.Locale.RegionalFormat -Name '区域格式' -Profiles @() -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $regionalFormatProperties
} -Apply {
    InitWin-SetRegistryProperties -Properties $regionalFormatProperties
}

InitWin-DefineEntry -Id System.Locale.Unicode -Name 'Non-Unicode locale / UTF-8 / 复制到欢迎屏 & 新用户' -Profiles @() -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    if ((Get-WinSystemLocale).Name -ne 'zh-CN') {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target 'WinSystemLocale' -Current (Get-WinSystemLocale).Name -Expected 'zh-CN'))
    }

    foreach ($registryResult in @(InitWin-TestRegistryPropertiesDesired -Properties $unicodeLocaleProperties)) {
        if ($registryResult.Status -ne 'Desired') { $results.Add($registryResult) }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    Set-WinSystemLocale -SystemLocale 'zh-CN'
    InitWin-SetRegistryProperties -Properties $unicodeLocaleProperties

    # 来源：https://learn.microsoft.com/en-us/powershell/module/international/copy-userinternationalsettingstosystem
    try {
        Import-Module International -ErrorAction Stop
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
    } catch {
        InitWin-WriteDetail "Copy-UserInternationalSettingsToSystem 不可用（需要 Windows 11+），跳过：$_" -ForegroundColor Yellow
    }
}
