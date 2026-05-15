$networkProfileProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\NetworkList\NetworkCategorization\UnidentifiedNetworks' -Name 'Category' -Type DWord -Value 1
)

InitWin-DefineEntry -Id System.Network.Profile -Name '网络' -Profiles @() -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($registryResult in @(InitWin-TestRegistryPropertiesDesired -Properties $networkProfileProperties)) {
        if ($registryResult.Status -ne 'Desired') { $results.Add($registryResult) }
    }

    foreach ($profile in @(Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -ne 'Private' })) {
        $interfaceName = $profile.InterfaceAlias
        if (-not $interfaceName) { $interfaceName = $profile.Name }
        if (-not $interfaceName) { $interfaceName = "interface index $($profile.InterfaceIndex)" }

        $results.Add((InitWin-NewValidationResult `
            -Status Unset `
            -Target "network interface `"$interfaceName`"" `
            -Current $profile.NetworkCategory `
            -Expected 'Private'))
    }
    if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff')) {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target 'registry key: HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff' -Current '<missing>' -Expected 'present'))
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
    InitWin-SetRegistryProperties -Properties $networkProfileProperties

    # 该 key 的存在即关闭“新网络弹窗”。
    $newNetworkWindow = 'HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff'
    if (-not (Test-Path -LiteralPath $newNetworkWindow)) { New-Item -Path $newNetworkWindow -Force | Out-Null }
}

InitWin-DefineEntry -Id System.Network.FirewallRules -Name '防火墙' -Profiles @() -Validate {
    $rules = Get-NetFirewallRule -DisplayName 'Allow ALL' -ErrorAction SilentlyContinue |
        Where-Object { ($_.Enabled -eq 'True') -and ($_.Direction -eq 'Inbound') -and ($_.Action -eq 'Allow') }
    foreach ($rule in $rules) {
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
        if ($portFilter.Protocol -eq 'Any') { return InitWin-NewValidationResult -Status Desired }
    }

    InitWin-NewValidationResult -Status Unset -Target 'firewall rule: Allow ALL inbound' -Current '<missing>' -Expected 'enabled allow any protocol'
} -Apply {
    Get-NetFirewallRule -DisplayName 'Allow ALL' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule `
        -DisplayName 'Allow ALL' `
        -Direction Inbound `
        -Action Allow `
        -Profile Domain,Private,Public `
        -Protocol Any `
        -Enabled True
}
