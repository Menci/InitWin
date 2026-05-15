$networkProfileProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\NetworkList\NetworkCategorization\UnidentifiedNetworks' -Name 'Category' -Type DWord -Value 1
)

InitWin-DefineEntry -Id System.Network.Profile -Validate {
    $registryResult = InitWin-TestRegistryPropertiesDesired -Properties $networkProfileProperties
    if ($registryResult.Status -ne 'Desired') { return $registryResult }

    $publicProfiles = Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -ne 'Private' }
    if ($publicProfiles) {
        return InitWin-NewValidationResult -Status Unset -Target 'network profiles' -Current 'non-private profile exists' -Expected 'all current profiles private'
    }
    if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff')) {
        return InitWin-NewValidationResult -Status Unset -Target 'registry key: HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff' -Current '<missing>' -Expected 'present'
    }

    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-WriteStep '网络'
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
    InitWin-SetRegistryProperties -Properties $networkProfileProperties

    # 该 key 的存在即关闭“新网络弹窗”。
    $newNetworkWindow = 'HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff'
    if (-not (Test-Path -LiteralPath $newNetworkWindow)) { New-Item -Path $newNetworkWindow -Force | Out-Null }
}

InitWin-DefineEntry -Id System.Network.FirewallRules -Validate {
    $rules = Get-NetFirewallRule -DisplayName 'Allow ALL' -ErrorAction SilentlyContinue |
        Where-Object { ($_.Enabled -eq 'True') -and ($_.Direction -eq 'Inbound') -and ($_.Action -eq 'Allow') }
    foreach ($rule in $rules) {
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
        if ($portFilter.Protocol -eq 'Any') { return InitWin-NewValidationResult -Status Desired }
    }

    InitWin-NewValidationResult -Status Unset -Target 'firewall rule: Allow ALL inbound' -Current '<missing>' -Expected 'enabled allow any protocol'
} -Apply {
    InitWin-WriteStep '防火墙'
    Get-NetFirewallRule -DisplayName 'Allow ALL' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule `
        -DisplayName 'Allow ALL' `
        -Direction Inbound `
        -Action Allow `
        -Profile Domain,Private,Public `
        -Protocol Any `
        -Enabled True
}
