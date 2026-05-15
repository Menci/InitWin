$remoteDesktopProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' -Name 'DWMFRAMEINTERVAL' -Type DWord -Value 15
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'AVC444ModePreferred' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'bEnumerateHWBeforeSW' -Type DWord -Value 1
)

InitWin-DefineEntry -Id System.RemoteAccess.RemoteDesktop -Name '远程桌面' -Profiles @() -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($registryResult in @(InitWin-TestRegistryPropertiesDesired -Properties $remoteDesktopProperties)) {
        if ($registryResult.Status -ne 'Desired') { $results.Add($registryResult) }
    }

    $firewallRules = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' }
    if (-not $firewallRules) {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target 'firewall group: Remote Desktop' -Current 'disabled' -Expected 'enabled'))
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-SetRegistryProperties -Properties $remoteDesktopProperties
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
}
