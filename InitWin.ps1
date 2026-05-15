# InitWin.ps1
# Windows 新机初始化入口。需要管理员权限运行。

param(
    [AllowNull()]
    [string] $Profile = $null,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $modulePaths = @(
        (Join-Path $PSHOME 'Modules')
        ([Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';')
        ([Environment]::GetEnvironmentVariable('PSModulePath', 'User') -split ';')
    ) |
        Where-Object { $_ -and ($_ -notmatch '\\PowerShell\\7\\Modules\\?$') } |
        Select-Object -Unique
    $env:PSModulePath = $modulePaths -join ';'
}

. (Join-Path $PSScriptRoot 'Lib\InitWin.Core.ps1')

InitWin-ResetEntries

$configPath = Join-Path $PSScriptRoot 'InitWin.config.psd1'
$config = @{
    Profile = $null
    IgnoredEntries = @()
}

if (Test-Path -LiteralPath $configPath) {
    $loadedConfig = Import-PowerShellDataFile -LiteralPath $configPath
    $knownConfigKeys = @('Profile', 'IgnoredEntries')
    foreach ($key in $loadedConfig.Keys) {
        if ($key -notin $knownConfigKeys) {
            throw "Unknown config key in $configPath`: $key"
        }
    }
    if ($loadedConfig.ContainsKey('Profile')) {
        $config.Profile = $loadedConfig.Profile
    }
    if ($loadedConfig.ContainsKey('IgnoredEntries')) {
        $config.IgnoredEntries = @($loadedConfig.IgnoredEntries)
    }
}

if ($PSBoundParameters.ContainsKey('Profile')) {
    $config.Profile = $Profile
}
if (($null -ne $config.Profile) -and ($config.Profile -notin @('Work', 'Personal'))) {
    throw "Profile must be Work or Personal: $($config.Profile)"
}
if ($null -eq $config.IgnoredEntries) {
    $config.IgnoredEntries = @()
}

$entryScripts = @()

$systemConfigRoot = Join-Path $PSScriptRoot 'SystemConfig'
if (Test-Path $systemConfigRoot) {
    $entryScripts += Get-ChildItem -LiteralPath $systemConfigRoot -Filter '*.ps1' -File | Sort-Object FullName
}

$packagesRoot = Join-Path $PSScriptRoot 'Packages'
if (Test-Path $packagesRoot) {
    $entryScripts += Get-ChildItem -LiteralPath $packagesRoot -Filter '*.ps1' -File | Sort-Object FullName
}

$appConfigRoot = Join-Path $PSScriptRoot 'AppConfig'
if (Test-Path $appConfigRoot) {
    $entryScripts += Get-ChildItem -LiteralPath $appConfigRoot -Directory |
        ForEach-Object { Join-Path $_.FullName 'Entries.ps1' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        ForEach-Object { Get-Item -LiteralPath $_ } |
        Sort-Object FullName
}

foreach ($script in $entryScripts) {
    . $script.FullName
}

InitWin-SetIgnoredEntries -Ids ([string[]] $config.IgnoredEntries)
InitWin-AssertIgnoredEntriesRegistered

$effectiveProfile = $config.Profile

if ($DryRun) {
    InitWin-WritePhase 'Dry run'
    InitWin-WritePhaseDetail '只检查当前状态，不执行 Apply。' -ForegroundColor Yellow
}

InitWin-WritePhase 'System configuration'
InitWin-InvokeEntries -Profile $effectiveProfile -DryRun:$DryRun -Ids @(
    'System.Security.ExecutionPolicy'
    'System.Personalization.Taskbar'
    'System.Personalization.ColorTheme'
    'System.Personalization.DesktopIcons'
    'System.Personalization.LockScreen'
    'System.Personalization.VisualEffects'
    'System.Shell.Multitasking'
    'System.Shell.Explorer'
    'System.RemoteAccess.RemoteDesktop'
    'System.Developer.TerminalAndSudo'
    'System.Network.Profile'
    'System.Network.FirewallRules'
    'System.Locale.DateTime'
    'System.Locale.RegionalFormat'
    'System.Locale.Unicode'
    'System.Features.WindowsCapabilities'
    'System.Features.WindowsOptionalFeatures'
    'System.Security.UacPolicy'
    'System.Security.Ucpd'
    'System.Power.PowerAndExplorer'
)

InitWin-WritePhase 'Microsoft Store packages'
InitWin-InvokeEntries -Profile $effectiveProfile -DryRun:$DryRun -Ids @(
    'Packages.MicrosoftStore.WindowsApp'
    'Packages.MicrosoftStore.Debian'
    'Packages.MicrosoftStore.Wsl'
    'Packages.MicrosoftStore.Gimp'
    'Packages.MicrosoftStore.Inkscape'
    'Packages.MicrosoftStore.TelegramDesktop'
    'Packages.MicrosoftStore.NanaZip'
    'Packages.MicrosoftStore.Mitmproxy'
    'Packages.MicrosoftStore.Snipaste'
    'Packages.MicrosoftStore.PowerToys'
    'Packages.MicrosoftStore.Python313'
    'Packages.MicrosoftStore.TwinkleTray'
)

InitWin-WritePhase 'WinGet packages'
InitWin-InvokeEntries -Profile $effectiveProfile -DryRun:$DryRun -Ids @(
    'Packages.WinGet.PowerShell'
    'Packages.WinGet.VisualStudioCode'
    'Packages.WinGet.GitForWindows'
    'Packages.WinGet.Bitwarden'
    'Packages.WinGet.Office365Apps'
    'Packages.WinGet.DotNetSdk'
    'Packages.WinGet.Vlc'
    'Packages.WinGet.Wireshark'
    'Packages.WinGet.AzureCli'
    'Packages.WinGet.Kubectl'
)

InitWin-WritePhase 'Extra packages'
InitWin-InvokeEntries -Profile $effectiveProfile -DryRun:$DryRun -Ids @(
    'Packages.Extras.Hevc'
    'Packages.Fonts.MapleMono'
)

InitWin-WritePhase 'Application configuration'
InitWin-InvokeEntries -Profile $effectiveProfile -DryRun:$DryRun -Ids @(
    'App.PowerToys.Config'
    'App.Snipaste.Config'
    'App.Telegram.Config'
    'App.WindowsTerminal.Config'
)

InitWin-AssertEntryPlanComplete
