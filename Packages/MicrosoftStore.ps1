$defineMicrosoftStorePackage = {
    param(
        [Parameter(Mandatory)][string] $EntryName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Id,
        [string[]] $AppxPackageNames = @(),
        [string[]] $WingetPackageIds = @(),
        [string[]] $CommandNames = @(),
        [string[]] $UninstallDisplayNamePatterns = @()
    )

    $nameLiteral = InitWin-QuotePowerShellString $Name
    $idLiteral = InitWin-QuotePowerShellString $Id
    $appxPackageNamesLiteral = InitWin-QuotePowerShellStringArray $AppxPackageNames
    $wingetPackageIdsLiteral = InitWin-QuotePowerShellStringArray $WingetPackageIds
    $commandNamesLiteral = InitWin-QuotePowerShellStringArray $CommandNames
    $uninstallDisplayNamePatternsLiteral = InitWin-QuotePowerShellStringArray $UninstallDisplayNamePatterns
    $targetLiteral = InitWin-QuotePowerShellString "Microsoft Store package: $Name ($Id)"

    $validate = [scriptblock]::Create((@(
        "`$ErrorActionPreference = 'Stop'"
        "if (InitWin-TestPackageInstalled ``"
        "    -AppxPackageNames $appxPackageNamesLiteral ``"
        "    -WingetPackageIds $wingetPackageIdsLiteral ``"
        "    -MsStorePackageIds @($idLiteral) ``"
        "    -CommandNames $commandNamesLiteral ``"
        "    -UninstallDisplayNamePatterns $uninstallDisplayNamePatternsLiteral) {"
        "    return InitWin-NewValidationResult -Status Desired"
        "}"
        ""
        "InitWin-NewValidationResult -Status Unset -Target $targetLiteral -Current '<missing>' -Expected 'installed'"
    ) -join [Environment]::NewLine))

    $apply = [scriptblock]::Create((@(
        "`$ErrorActionPreference = 'Stop'"
        "InitWin-InstallWingetPackage -Name $nameLiteral -Id $idLiteral -Source msstore"
    ) -join [Environment]::NewLine))

    InitWin-DefineEntry -Id "Packages.MicrosoftStore.$EntryName" -Name "Microsoft Store: $Name" -Validate $validate -Apply $apply
}

& $defineMicrosoftStorePackage -EntryName WindowsApp -Name 'Windows App (msrdc)' -Id '9N1F85V9T8BN' `
    -AppxPackageNames @('MicrosoftCorporationII.Windows365') `
    -WingetPackageIds @('Microsoft.WindowsApp')
& $defineMicrosoftStorePackage -EntryName Debian -Name 'Debian (WSL)' -Id '9MSVKQC78PK6' `
    -AppxPackageNames @('TheDebianProject.DebianGNULinux') `
    -WingetPackageIds @('Debian.Debian')
& $defineMicrosoftStorePackage -EntryName Wsl -Name 'WSL (Microsoft Store)' -Id '9P9TQF7MRM4R' `
    -WingetPackageIds @('Microsoft.WSL')
& $defineMicrosoftStorePackage -EntryName Gimp -Name 'GIMP' -Id '9PNSJCLXDZ0V' `
    -AppxPackageNames @('GIMP.43237F745459') `
    -WingetPackageIds @('GIMP.GIMP', 'GIMP.GIMP.3') `
    -UninstallDisplayNamePatterns @('GIMP*')
& $defineMicrosoftStorePackage -EntryName Inkscape -Name 'Inkscape' -Id '9PD9BHGLFC7H' `
    -AppxPackageNames @('25415Inkscape.Inkscape') `
    -WingetPackageIds @('Inkscape.Inkscape') `
    -CommandNames @('inkscape.exe') `
    -UninstallDisplayNamePatterns @('Inkscape*')
& $defineMicrosoftStorePackage -EntryName TelegramDesktop -Name 'Telegram Desktop' -Id '9NZTWSQNTD0S' `
    -AppxPackageNames @('TelegramMessengerLLP.TelegramDesktop') `
    -WingetPackageIds @('Telegram.TelegramDesktop') `
    -UninstallDisplayNamePatterns @('Telegram Desktop*')
& $defineMicrosoftStorePackage -EntryName NanaZip -Name 'NanaZip' -Id '9N8G7TSCL18R' `
    -AppxPackageNames @('40174MouriNaruto.NanaZip') `
    -WingetPackageIds @('M2Team.NanaZip')
& $defineMicrosoftStorePackage -EntryName Mitmproxy -Name 'mitmproxy' -Id '9NWNDLQMNZD7' `
    -AppxPackageNames @('8637MaximilianHils.mitmproxy') `
    -WingetPackageIds @('mitmproxy.mitmproxy') `
    -CommandNames @('mitmproxy.exe', 'mitmdump.exe', 'mitmweb.exe') `
    -UninstallDisplayNamePatterns @('mitmproxy*')
& $defineMicrosoftStorePackage -EntryName Snipaste -Name 'Snipaste' -Id '9P1WXPKB68KX' `
    -AppxPackageNames @('45479liulios.17062D84F7C46') `
    -WingetPackageIds @('liule.Snipaste') `
    -CommandNames @('Snipaste.exe') `
    -UninstallDisplayNamePatterns @('Snipaste*')
& $defineMicrosoftStorePackage -EntryName PowerToys -Name 'PowerToys' -Id 'XP89DCGQ3K6VLD' `
    -WingetPackageIds @('Microsoft.PowerToys') `
    -UninstallDisplayNamePatterns @('PowerToys*')
& $defineMicrosoftStorePackage -EntryName Python313 -Name 'Python 3.13' -Id '9PNRBTZXMB4Z' `
    -AppxPackageNames @('PythonSoftwareFoundation.Python.3.13')
& $defineMicrosoftStorePackage -EntryName TwinkleTray -Name 'Twinkle Tray' -Id '9PLJWWSV01LK' `
    -AppxPackageNames @('38002AlexanderFrangos.TwinkleTray') `
    -WingetPackageIds @('xanderfrangos.twinkletray') `
    -UninstallDisplayNamePatterns @('Twinkle Tray*')
