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

InitWin-DefineEntry -Id System.Features.WindowsCapabilities -Name 'Optional features (FoD)' -Validate {
    $capabilityNamesLiteral = InitWin-QuotePowerShellStringArray $windowsCapabilityNames
    $script = @"
`$results = foreach (`$capability in $capabilityNamesLiteral) {
    `$state = Get-WindowsCapability -Online -Name `$capability -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name = `$capability
        State = if (`$null -eq `$state) { '<missing>' } else { [string] `$state.State }
    }
}
`$results | ConvertTo-Json -Depth 4
"@
    $states = @(InitWin-InvokeWindowsPowerShellJson -Script $script)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($state in $states) {
        if ($state.State -ne 'Installed') {
            $results.Add((InitWin-NewValidationResult -Status Unset -Target "Windows capability: $($state.Name)" -Current $state.State -Expected 'Installed'))
        }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    $capabilityNamesLiteral = InitWin-QuotePowerShellStringArray $windowsCapabilityNames
    $script = @"
foreach (`$capability in $capabilityNamesLiteral) {
    `$state = Get-WindowsCapability -Online -Name `$capability -ErrorAction SilentlyContinue
    if (`$null -eq `$state) {
        Write-Warning "Capability 不存在于本机：`$capability"
        continue
    }
    if (`$state.State -ne 'Installed') {
        Write-Host "Installing optional feature: `$capability"
        Add-WindowsCapability -Online -Name `$capability | Out-Null
    }
}
"@
    foreach ($line in @(InitWin-InvokeWindowsPowerShell -Script $script -CaptureOutput)) {
        InitWin-WriteDetail ([string] $line)
    }
}

InitWin-DefineEntry -Id System.Features.WindowsOptionalFeatures -Name 'Windows features' -Validate {
    $featureNamesLiteral = InitWin-QuotePowerShellStringArray $windowsFeatureNames
    $script = @"
`$results = foreach (`$feature in $featureNamesLiteral) {
    `$state = Get-WindowsOptionalFeature -Online -FeatureName `$feature -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name = `$feature
        State = if (`$null -eq `$state) { '<missing>' } else { [string] `$state.State }
    }
}
`$results | ConvertTo-Json -Depth 4
"@
    $states = @(InitWin-InvokeWindowsPowerShellJson -Script $script)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($state in $states) {
        if ($state.State -ne 'Enabled') {
            $results.Add((InitWin-NewValidationResult -Status Unset -Target "Windows optional feature: $($state.Name)" -Current $state.State -Expected 'Enabled'))
        }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    $featureNamesLiteral = InitWin-QuotePowerShellStringArray $windowsFeatureNames
    $script = @"
foreach (`$feature in $featureNamesLiteral) {
    `$state = Get-WindowsOptionalFeature -Online -FeatureName `$feature -ErrorAction SilentlyContinue
    if (`$null -eq `$state) {
        Write-Warning "Windows feature 不存在于本机：`$feature"
        continue
    }
    if (`$state.State -ne 'Enabled') {
        Write-Host "Enabling Windows feature: `$feature"
        Enable-WindowsOptionalFeature -Online -FeatureName `$feature -All -NoRestart | Out-Null
    }
}
"@
    foreach ($line in @(InitWin-InvokeWindowsPowerShell -Script $script -CaptureOutput)) {
        InitWin-WriteDetail ([string] $line)
    }
}
