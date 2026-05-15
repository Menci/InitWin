$windowsCapabilityNames = @(
    'Language.Fonts.Hans~~~und-HANS~0.0.1.0'
)

$basicWindowsCapabilityNames = @(
    'OpenSSH.Client~~~~0.0.1.0'
)

$windowsFeatureNames = @(
    'Microsoft-Hyper-V-All'
    'Microsoft-Windows-Subsystem-Linux'
    'VirtualMachinePlatform'
    'Containers-DisposableClientVM'
)

$basicWindowsFeatureNames = @(
    'TelnetClient'
    'TFTP'
)

$defineWindowsCapabilityEntry = {
    param(
        [Parameter(Mandatory)][string] $EntryName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string[]] $CapabilityNames,
        [string[]] $Profiles = @()
    )

    $capabilityNamesLiteral = InitWin-QuotePowerShellStringArray $CapabilityNames
    $validateScript = @"
`$ErrorActionPreference = 'Stop'
`$results = foreach (`$capability in $capabilityNamesLiteral) {
    `$state = Get-WindowsCapability -Online -Name `$capability -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name = `$capability
        State = if (`$null -eq `$state) { '<missing>' } else { [string] `$state.State }
    }
}
`$results | ConvertTo-Json -Depth 4
"@

    $applyScript = @"
`$ErrorActionPreference = 'Stop'
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

    $validateScriptLiteral = InitWin-QuotePowerShellString $validateScript
    $applyScriptLiteral = InitWin-QuotePowerShellString $applyScript
    $entryValidate = [scriptblock]::Create(@"
`$ErrorActionPreference = 'Stop'
`$states = @(InitWin-InvokeWindowsPowerShellJson -Script $validateScriptLiteral)
`$results = [System.Collections.Generic.List[object]]::new()
foreach (`$state in `$states) {
    if (`$state.State -ne 'Installed') {
        `$results.Add((InitWin-NewValidationResult -Status Unset -Target "Windows capability: `$(`$state.Name)" -Current `$state.State -Expected 'Installed'))
    }
}

if (`$results.Count -gt 0) { return `$results }
InitWin-NewValidationResult -Status Desired
"@)
    $entryApply = [scriptblock]::Create(@"
`$ErrorActionPreference = 'Stop'
foreach (`$line in @(InitWin-InvokeWindowsPowerShell -Script $applyScriptLiteral -CaptureOutput)) {
    InitWin-WriteDetail ([string] `$line)
}
"@)

    InitWin-DefineEntry -Id "System.Features.$EntryName" -Name $Name -Profiles $Profiles -Validate $entryValidate -Apply $entryApply
}

$defineWindowsOptionalFeatureEntry = {
    param(
        [Parameter(Mandatory)][string] $EntryName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string[]] $FeatureNames,
        [string[]] $Profiles = @()
    )

    $featureNamesLiteral = InitWin-QuotePowerShellStringArray $FeatureNames
    $validateScript = @"
`$ErrorActionPreference = 'Stop'
`$results = foreach (`$feature in $featureNamesLiteral) {
    `$state = Get-WindowsOptionalFeature -Online -FeatureName `$feature -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name = `$feature
        State = if (`$null -eq `$state) { '<missing>' } else { [string] `$state.State }
    }
}
`$results | ConvertTo-Json -Depth 4
"@

    $applyScript = @"
`$ErrorActionPreference = 'Stop'
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

    $validateScriptLiteral = InitWin-QuotePowerShellString $validateScript
    $applyScriptLiteral = InitWin-QuotePowerShellString $applyScript
    $entryValidate = [scriptblock]::Create(@"
`$ErrorActionPreference = 'Stop'
`$states = @(InitWin-InvokeWindowsPowerShellJson -Script $validateScriptLiteral)
`$results = [System.Collections.Generic.List[object]]::new()
foreach (`$state in `$states) {
    if (`$state.State -ne 'Enabled') {
        `$results.Add((InitWin-NewValidationResult -Status Unset -Target "Windows optional feature: `$(`$state.Name)" -Current `$state.State -Expected 'Enabled'))
    }
}

if (`$results.Count -gt 0) { return `$results }
InitWin-NewValidationResult -Status Desired
"@)
    $entryApply = [scriptblock]::Create(@"
`$ErrorActionPreference = 'Stop'
foreach (`$line in @(InitWin-InvokeWindowsPowerShell -Script $applyScriptLiteral -CaptureOutput)) {
    InitWin-WriteDetail ([string] `$line)
}
"@)

    InitWin-DefineEntry -Id "System.Features.$EntryName" -Name $Name -Profiles $Profiles -Validate $entryValidate -Apply $entryApply
}

& $defineWindowsCapabilityEntry `
    -EntryName WindowsCapabilities `
    -Name 'Optional features (FoD)' `
    -Profiles @('!Basic') `
    -CapabilityNames $windowsCapabilityNames
& $defineWindowsCapabilityEntry `
    -EntryName WindowsCapabilities.Basic `
    -Name 'Optional features (FoD) basic' `
    -Profiles @() `
    -CapabilityNames $basicWindowsCapabilityNames

& $defineWindowsOptionalFeatureEntry `
    -EntryName WindowsOptionalFeatures `
    -Name 'Windows features' `
    -Profiles @('!Basic') `
    -FeatureNames $windowsFeatureNames
& $defineWindowsOptionalFeatureEntry `
    -EntryName WindowsOptionalFeatures.Basic `
    -Name 'Windows features basic' `
    -Profiles @() `
    -FeatureNames $basicWindowsFeatureNames
