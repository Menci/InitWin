$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$accent = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
$dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
$hideIcons = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
$systemPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
$contentDeliveryManager = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$personalizationCsp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
$visualEffects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
$widgetsPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'

$taskbarProperties = @(
    InitWin-NewRegistryProperty -Path $search -Name 'SearchboxTaskbarMode' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $advanced -Name 'ShowTaskViewButton' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $advanced -Name 'TaskbarAl' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $advanced -Name 'MMTaskbarEnabled' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $advanced -Name 'MMTaskbarMode' -Type DWord -Value 2
    # TaskbarDa is UCPD-protected on current Windows builds; use the supported Widgets policy instead.
    # Reference: https://learn.microsoft.com/windows/client-management/mdm/policy-csp-newsandinterests#allownewsandinterests
    InitWin-NewRegistryProperty -Path $widgetsPolicy -Name 'AllowNewsAndInterests' -Type DWord -Value 0
)

# Orchid Light dump：Accent/DWM DWORD 为 ABGR，DWM Colorization* 为 ARGB，AccentPalette 为 8 槽 RGBA。
$colorThemeProperties = @(
    InitWin-NewRegistryProperty -Path $personalize -Name 'AppsUseLightTheme' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $personalize -Name 'SystemUsesLightTheme' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $accent -Name 'AccentColorMenu' -Type DWord -Value 0xFFB339C2
    InitWin-NewRegistryProperty -Path $accent -Name 'StartColorMenu' -Type DWord -Value 0xFFA030AE
    InitWin-NewRegistryProperty -Path $dwm -Name 'AccentColor' -Type DWord -Value 0xFFB339C2
    InitWin-NewRegistryProperty -Path $dwm -Name 'ColorizationColor' -Type DWord -Value 0xC4C239B3
    InitWin-NewRegistryProperty -Path $dwm -Name 'ColorizationAfterglow' -Type DWord -Value 0xC4C239B3
    InitWin-NewRegistryProperty -Path $dwm -Name 'ColorizationColorBalance' -Type DWord -Value 89
    InitWin-NewRegistryProperty -Path $dwm -Name 'ColorPrevalence' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $personalize -Name 'ColorPrevalence' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $accent -Name 'AccentPalette' -Type Binary -Value ([byte[]](
        0xF4,0xB2,0xF1, 0x00,
        0xE1,0x83,0xD9, 0x00,
        0xCB,0x4F,0xBF, 0x00,
        0xC2,0x39,0xB3, 0x00,
        0xAE,0x30,0xA0, 0x00,
        0x7F,0x1D,0x75, 0x00,
        0x54,0x0A,0x4D, 0x00,
        0x2D,0x7D,0x9A, 0x00
    ))
    InitWin-NewRegistryProperty -Path $personalize -Name 'EnableTransparency' -Type DWord -Value 1
)

$desktopIconProperties = @(
    InitWin-NewRegistryProperty -Path $hideIcons -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $hideIcons -Name '{59031A47-3F72-44A7-89C5-5595FE6B30EE}' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $hideIcons -Name '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $hideIcons -Name '{645FF040-5081-101B-9F08-00AA002F954E}' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $hideIcons -Name '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}' -Type DWord -Value 1
)

$lockScreenProperties = @(
    InitWin-NewRegistryProperty -Path $systemPolicy -Name 'DisableLogonBackgroundImage' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $contentDeliveryManager -Name 'RotatingLockScreenEnabled' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $contentDeliveryManager -Name 'RotatingLockScreenOverlayEnabled' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $contentDeliveryManager -Name 'SubscribedContent-338387Enabled' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $contentDeliveryManager -Name 'SubscribedContent-338380Enabled' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $personalizationCsp -Name 'LockScreenWidgetsEnabled' -Type DWord -Value 0
)

$visualEffectProperties = @(
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Type Binary -Value ([byte[]](0x90,0x12,0x07,0x80,0x10,0x00,0x00,0x00))
    InitWin-NewRegistryProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Type String -Value '0'
    InitWin-NewRegistryProperty -Path $advanced -Name 'ListviewAlphaSelect' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path $advanced -Name 'ListviewShadow' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path $visualEffects -Name 'VisualFXSetting' -Type DWord -Value 3
)

InitWin-DefineEntry -Id System.Personalization.Taskbar -Name '任务栏' -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $taskbarProperties
} -Apply {
    InitWin-SetRegistryProperties -Properties $taskbarProperties
}

InitWin-DefineEntry -Id System.Personalization.ColorTheme -Name '颜色 / accent / 透明' -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $colorThemeProperties
} -Apply {
    # Orchid Light 来源：https://jmacthefatcat.github.io/win-10-colours/
    # Accent 编码参考：https://github.com/Valer100/winaccent
    InitWin-SetRegistryProperties -Properties $colorThemeProperties
}

InitWin-DefineEntry -Id System.Personalization.DesktopIcons -Name '桌面图标' -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $desktopIconProperties
} -Apply {
    InitWin-SetRegistryProperties -Properties $desktopIconProperties
}

InitWin-DefineEntry -Id System.Personalization.LockScreen -Name '锁屏' -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $lockScreenProperties
} -Apply {
    # LockScreenWidgetsEnabled 参考：https://woshub.com/lock-screen-widgets-windows/
    InitWin-SetRegistryProperties -Properties $lockScreenProperties
}

InitWin-DefineEntry -Id System.Personalization.VisualEffects -Name 'Visual effects' -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $visualEffectProperties
} -Apply {
    InitWin-SetRegistryProperties -Properties $visualEffectProperties

    $systemParametersInfoDefinition = @(
        'using System;'
        'using System.Runtime.InteropServices;'
        'public static class SPI {'
        '    [DllImport("user32.dll", SetLastError = true)]'
        '    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, UIntPtr pvParam, uint fWinIni);'
        '}'
    ) -join [Environment]::NewLine
    Add-Type -TypeDefinition $systemParametersInfoDefinition -ErrorAction SilentlyContinue
    # SPI_SETCLIENTAREAANIMATION = 0x1043; SPIF_UPDATEINIFILE|SPIF_SENDCHANGE = 0x03
    [void][SPI]::SystemParametersInfo(0x1043, 0, [UIntPtr]::Zero, 0x03)
}
