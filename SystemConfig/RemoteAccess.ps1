$remoteDesktopProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' -Name 'DWMFRAMEINTERVAL' -Type DWord -Value 15
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'AVC444ModePreferred' -Type DWord -Value 1
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'bEnumerateHWBeforeSW' -Type DWord -Value 1
)

InitWin-DefineEntry -Id System.RemoteAccess.RemoteDesktop -Validate {
    $registryResult = InitWin-TestRegistryPropertiesDesired -Properties $remoteDesktopProperties
    if ($registryResult.Status -ne 'Desired') { return $registryResult }

    $firewallRules = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' }
    if (-not $firewallRules) {
        return InitWin-NewValidationResult -Status Unset -Target 'firewall group: Remote Desktop' -Current 'disabled' -Expected 'enabled'
    }

    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-WriteStep '远程桌面'
    InitWin-SetRegistryProperties -Properties $remoteDesktopProperties
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
}
