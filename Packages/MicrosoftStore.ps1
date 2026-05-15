$quotePowerShellString = {
    param([Parameter(Mandatory)][string] $Value)

    "'$($Value.Replace("'", "''"))'"
}

$quotePowerShellStringArray = {
    param([string[]] $Values = @())

    $items = @($Values | ForEach-Object { & $quotePowerShellString $_ })
    '@(' + ($items -join ', ') + ')'
}

$defineMicrosoftStorePackage = {
    param(
        [Parameter(Mandatory)][string] $EntryName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Id,
        [string[]] $AppxPackageNames = @(),
        [string[]] $WingetPackageIds = @()
    )

    $nameLiteral = & $quotePowerShellString $Name
    $idLiteral = & $quotePowerShellString $Id
    $appxPackageNamesLiteral = & $quotePowerShellStringArray $AppxPackageNames
    $wingetPackageIdsLiteral = & $quotePowerShellStringArray $WingetPackageIds
    $targetLiteral = & $quotePowerShellString "Microsoft Store package: $Name ($Id)"
    $stepLiteral = & $quotePowerShellString "Microsoft Store: $Name"

    $validate = [scriptblock]::Create((@(
        "foreach (`$appxPackageName in $appxPackageNamesLiteral) {"
        "    if (Get-AppxPackage -Name `$appxPackageName -ErrorAction SilentlyContinue) {"
        "        return InitWin-NewValidationResult -Status Desired"
        "    }"
        "}"
        ""
        "foreach (`$wingetPackageId in $wingetPackageIdsLiteral) {"
        "    if (InitWin-TestWingetPackageInstalled -Id `$wingetPackageId -Source winget) {"
        "        return InitWin-NewValidationResult -Status Desired"
        "    }"
        "}"
        ""
        "if (InitWin-TestWingetPackageInstalled -Id $idLiteral -Source msstore) {"
        "    return InitWin-NewValidationResult -Status Desired"
        "}"
        ""
        "InitWin-NewValidationResult -Status Unset -Target $targetLiteral -Current '<missing>' -Expected 'installed'"
    ) -join [Environment]::NewLine))

    $apply = [scriptblock]::Create((@(
        "InitWin-WriteStep $stepLiteral"
        "InitWin-InstallWingetPackage -Name $nameLiteral -Id $idLiteral -Source msstore"
    ) -join [Environment]::NewLine))

    InitWin-DefineEntry -Id "Packages.MicrosoftStore.$EntryName" -Validate $validate -Apply $apply
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
    -AppxPackageNames @('GIMP.43237F745459')
& $defineMicrosoftStorePackage -EntryName Inkscape -Name 'Inkscape' -Id '9PD9BHGLFC7H' `
    -AppxPackageNames @('25415Inkscape.Inkscape')
& $defineMicrosoftStorePackage -EntryName TelegramDesktop -Name 'Telegram Desktop' -Id '9NZTWSQNTD0S' `
    -AppxPackageNames @('TelegramMessengerLLP.TelegramDesktop')
& $defineMicrosoftStorePackage -EntryName NanaZip -Name 'NanaZip' -Id '9N8G7TSCL18R' `
    -AppxPackageNames @('40174MouriNaruto.NanaZip') `
    -WingetPackageIds @('M2Team.NanaZip')
& $defineMicrosoftStorePackage -EntryName Mitmproxy -Name 'mitmproxy' -Id '9NWNDLQMNZD7' `
    -AppxPackageNames @('8637MaximilianHils.mitmproxy')
& $defineMicrosoftStorePackage -EntryName Snipaste -Name 'Snipaste' -Id '9P1WXPKB68KX' `
    -AppxPackageNames @('45479liulios.17062D84F7C46')
& $defineMicrosoftStorePackage -EntryName PowerToys -Name 'PowerToys' -Id 'XP89DCGQ3K6VLD' `
    -WingetPackageIds @('Microsoft.PowerToys')
& $defineMicrosoftStorePackage -EntryName Python313 -Name 'Python 3.13' -Id '9PNRBTZXMB4Z' `
    -AppxPackageNames @('PythonSoftwareFoundation.Python.3.13')
& $defineMicrosoftStorePackage -EntryName TwinkleTray -Name 'Twinkle Tray' -Id '9PLJWWSV01LK' `
    -AppxPackageNames @('38002AlexanderFrangos.TwinkleTray')
