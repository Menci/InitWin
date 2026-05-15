$defineWinGetPackage = {
    param(
        [Parameter(Mandatory)][string] $EntryName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Id,
        [scriptblock] $ExtraValidate = $null,
        [scriptblock] $ExtraApply = $null,
        [string[]] $AppxPackageNames = @(),
        [string[]] $MsStorePackageIds = @(),
        [string[]] $CommandNames = @(),
        [string[]] $UninstallDisplayNamePatterns = @(),
        [string[]] $Profiles = @()
    )

    $nameLiteral = InitWin-QuotePowerShellString $Name
    $idLiteral = InitWin-QuotePowerShellString $Id
    $appxPackageNamesLiteral = InitWin-QuotePowerShellStringArray $AppxPackageNames
    $msStorePackageIdsLiteral = InitWin-QuotePowerShellStringArray $MsStorePackageIds
    $commandNamesLiteral = InitWin-QuotePowerShellStringArray $CommandNames
    $uninstallDisplayNamePatternsLiteral = InitWin-QuotePowerShellStringArray $UninstallDisplayNamePatterns
    $targetLiteral = InitWin-QuotePowerShellString "WinGet package: $Name ($Id)"
    $extraValidateSource = if ($ExtraValidate) { $ExtraValidate.ToString() } else { '' }
    $extraApplySource = if ($ExtraApply) { $ExtraApply.ToString() } else { '' }

    $validate = [scriptblock]::Create((@(
        "`$ErrorActionPreference = 'Stop'"
        "`$extraValidate = if ([string]::IsNullOrWhiteSpace(@'"
        $extraValidateSource
        "'@)) { `$null } else { [scriptblock]::Create(@'"
        $extraValidateSource
        "'@) }"
        '$results = [System.Collections.Generic.List[object]]::new()'
        '$installed = InitWin-TestPackageInstalled `'
        "    -AppxPackageNames $appxPackageNamesLiteral ``"
        "    -WingetPackageIds @($idLiteral) ``"
        "    -MsStorePackageIds $msStorePackageIdsLiteral ``"
        "    -CommandNames $commandNamesLiteral ``"
        "    -UninstallDisplayNamePatterns $uninstallDisplayNamePatternsLiteral"
        'if (-not $installed) {'
        "    `$results.Add((InitWin-NewValidationResult -Status Unset -Target $targetLiteral -Current '<missing>' -Expected 'installed'))"
        '}'
        'if ($installed -and $extraValidate) {'
        '    foreach ($result in @(InitWin-NormalizeValidationResults -Result (& $extraValidate))) {'
        "        if (`$result.Status -ne 'Desired') { `$results.Add(`$result) }"
        '    }'
        '}'
        'if ($results.Count -gt 0) { return $results }'
        'InitWin-NewValidationResult -Status Desired'
    ) -join [Environment]::NewLine))

    $apply = [scriptblock]::Create((@(
        "`$ErrorActionPreference = 'Stop'"
        "`$extraApply = if ([string]::IsNullOrWhiteSpace(@'"
        $extraApplySource
        "'@)) { `$null } else { [scriptblock]::Create(@'"
        $extraApplySource
        "'@) }"
        '$installed = InitWin-TestPackageInstalled `'
        "    -AppxPackageNames $appxPackageNamesLiteral ``"
        "    -WingetPackageIds @($idLiteral) ``"
        "    -MsStorePackageIds $msStorePackageIdsLiteral ``"
        "    -CommandNames $commandNamesLiteral ``"
        "    -UninstallDisplayNamePatterns $uninstallDisplayNamePatternsLiteral"
        ""
        'if (-not $installed) {'
        "InitWin-InstallWingetPackage -Name $nameLiteral -Id $idLiteral -Source winget"
        '}'
        'if ($extraApply) { & $extraApply }'
    ) -join [Environment]::NewLine))

    InitWin-DefineEntry -Id "Packages.WinGet.$EntryName" -Name "WinGet: $Name" -Profiles $Profiles -Validate $validate -Apply $apply
}

& $defineWinGetPackage -EntryName Basic.PowerShell -Name 'PowerShell' -Id 'Microsoft.PowerShell' `
    -ExtraValidate { InitWin-TestPowerShellCoreExecutionPolicy -Expected 'Bypass' } `
    -ExtraApply { InitWin-SetPowerShellCoreExecutionPolicy -Policy 'Bypass' } `
    -CommandNames @('pwsh.exe') `
    -UninstallDisplayNamePatterns @('PowerShell *')
& $defineWinGetPackage -EntryName Basic.Python314 -Name 'Python 3.14' -Id 'Python.Python.3.14' `
    -UninstallDisplayNamePatterns @('Python 3.14*')
& $defineWinGetPackage -EntryName VisualStudioCode -Name 'Visual Studio Code' -Id 'Microsoft.VisualStudioCode' `
    -CommandNames @('code.cmd', 'code.exe') `
    -UninstallDisplayNamePatterns @('Microsoft Visual Studio Code*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName Basic.GitForWindows -Name 'Git for Windows' -Id 'Git.Git' `
    -CommandNames @('git.exe') `
    -UninstallDisplayNamePatterns @('Git version *')
& $defineWinGetPackage -EntryName Bitwarden -Name 'Bitwarden' -Id 'Bitwarden.Bitwarden' `
    -UninstallDisplayNamePatterns @('Bitwarden*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName Office365Apps -Name 'Office 365 Apps' -Id 'Microsoft.Office' `
    -UninstallDisplayNamePatterns @('Microsoft 365*', 'Microsoft Office*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName DotNetSdk -Name '.NET SDK' -Id 'Microsoft.DotNet.SDK.10' `
    -UninstallDisplayNamePatterns @('Microsoft .NET SDK 10*', '.NET SDK 10*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName Vlc -Name 'VLC' -Id 'VideoLAN.VLC' `
    -CommandNames @('vlc.exe') `
    -UninstallDisplayNamePatterns @('VLC media player*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName Wireshark -Name 'Wireshark' -Id 'WiresharkFoundation.Wireshark' `
    -CommandNames @('Wireshark.exe', 'tshark.exe') `
    -UninstallDisplayNamePatterns @('Wireshark*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName AzureCli -Name 'Azure CLI' -Id 'Microsoft.AzureCLI' `
    -CommandNames @('az.cmd', 'az.exe') `
    -UninstallDisplayNamePatterns @('Microsoft Azure CLI*') `
    -Profiles @('!Basic')
& $defineWinGetPackage -EntryName Kubectl -Name 'kubectl' -Id 'Kubernetes.kubectl' `
    -CommandNames @('kubectl.exe') `
    -UninstallDisplayNamePatterns @('Kubernetes kubectl*') `
    -Profiles @('!Basic')
