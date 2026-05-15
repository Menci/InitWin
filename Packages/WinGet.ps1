$quotePowerShellString = {
    param([Parameter(Mandatory)][string] $Value)

    "'$($Value.Replace("'", "''"))'"
}

$defineWinGetPackage = {
    param(
        [Parameter(Mandatory)][string] $EntryName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Id
    )

    $nameLiteral = & $quotePowerShellString $Name
    $idLiteral = & $quotePowerShellString $Id
    $targetLiteral = & $quotePowerShellString "WinGet package: $Name ($Id)"
    $stepLiteral = & $quotePowerShellString "WinGet: $Name"

    $validate = [scriptblock]::Create((@(
        "if (InitWin-TestWingetPackageInstalled -Id $idLiteral -Source winget) {"
        "    return InitWin-NewValidationResult -Status Desired"
        "}"
        ""
        "InitWin-NewValidationResult -Status Unset -Target $targetLiteral -Current '<missing>' -Expected 'installed'"
    ) -join [Environment]::NewLine))

    $apply = [scriptblock]::Create((@(
        "InitWin-WriteStep $stepLiteral"
        "InitWin-InstallWingetPackage -Name $nameLiteral -Id $idLiteral -Source winget"
    ) -join [Environment]::NewLine))

    InitWin-DefineEntry -Id "Packages.WinGet.$EntryName" -Validate $validate -Apply $apply
}

& $defineWinGetPackage -EntryName PowerShell -Name 'PowerShell' -Id 'Microsoft.PowerShell'
& $defineWinGetPackage -EntryName VisualStudioCode -Name 'Visual Studio Code' -Id 'Microsoft.VisualStudioCode'
& $defineWinGetPackage -EntryName GitForWindows -Name 'Git for Windows' -Id 'Git.Git'
& $defineWinGetPackage -EntryName Bitwarden -Name 'Bitwarden' -Id 'Bitwarden.Bitwarden'
& $defineWinGetPackage -EntryName Office365Apps -Name 'Office 365 Apps' -Id 'Microsoft.Office'
& $defineWinGetPackage -EntryName DotNetSdk -Name '.NET SDK' -Id 'Microsoft.DotNet.SDK.10'
& $defineWinGetPackage -EntryName Vlc -Name 'VLC' -Id 'VideoLAN.VLC'
& $defineWinGetPackage -EntryName Wireshark -Name 'Wireshark' -Id 'WiresharkFoundation.Wireshark'
& $defineWinGetPackage -EntryName AzureCli -Name 'Azure CLI' -Id 'Microsoft.AzureCLI'
& $defineWinGetPackage -EntryName Kubectl -Name 'kubectl' -Id 'Kubernetes.kubectl'
