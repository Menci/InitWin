$windowsCapabilityNames = @(
    'Language.Fonts.Hans~~~und-HANS~0.0.1.0'
    'OpenSSH.Client~~~~0.0.1.0'
)

$windowsFeatureNames = @(
    'Microsoft-Hyper-V-All'
    'Microsoft-Windows-Subsystem-Linux'
    'VirtualMachinePlatform'
    'TelnetClient'
    'TFTP'
    'Containers-DisposableClientVM'
)

InitWin-DefineEntry -Id System.Features.WindowsCapabilities -Validate {
    foreach ($capability in $windowsCapabilityNames) {
        $state = Get-WindowsCapability -Online -Name $capability -ErrorAction SilentlyContinue
        if ($null -eq $state) {
            return InitWin-NewValidationResult -Status Unset -Target "Windows capability: $capability" -Current '<missing>' -Expected 'Installed'
        }
        if ($state.State -ne 'Installed') {
            return InitWin-NewValidationResult -Status Unset -Target "Windows capability: $capability" -Current $state.State -Expected 'Installed'
        }
    }

    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-WriteStep 'Optional features (FoD)'
    foreach ($capability in $windowsCapabilityNames) {
        $state = Get-WindowsCapability -Online -Name $capability -ErrorAction SilentlyContinue
        if ($null -eq $state) {
            InitWin-WriteDetail "Capability 不存在于本机：$capability" -ForegroundColor Yellow
            continue
        }
        if ($state.State -ne 'Installed') {
            InitWin-WriteDetail "Installing optional feature: $capability"
            Add-WindowsCapability -Online -Name $capability | Out-Null
        }
    }
}

InitWin-DefineEntry -Id System.Features.WindowsOptionalFeatures -Validate {
    foreach ($feature in $windowsFeatureNames) {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
        if ($null -eq $state) {
            return InitWin-NewValidationResult -Status Unset -Target "Windows optional feature: $feature" -Current '<missing>' -Expected 'Enabled'
        }
        if ($state.State -ne 'Enabled') {
            return InitWin-NewValidationResult -Status Unset -Target "Windows optional feature: $feature" -Current $state.State -Expected 'Enabled'
        }
    }

    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-WriteStep 'Windows features'
    foreach ($feature in $windowsFeatureNames) {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
        if ($null -eq $state) {
            InitWin-WriteDetail "Windows feature 不存在于本机：$feature" -ForegroundColor Yellow
            continue
        }
        if ($state.State -ne 'Enabled') {
            InitWin-WriteDetail "Enabling Windows feature: $feature"
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
        }
    }
}
