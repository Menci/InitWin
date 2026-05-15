function InitWin-NewRegistryProperty {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)]
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString')]
        [string] $Type,
        [Parameter(Mandatory)][object] $Value
    )

    [pscustomobject]@{
        Path = $Path
        Name = $Name
        Type = $Type
        Value = $Value
    }
}

function InitWin-ConvertDWordValue {
    param([Parameter(Mandatory)][object] $Value)

    if ($Value -is [int]) {
        return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int] $Value), 0)
    }

    [uint32] $Value
}

function InitWin-TestValueEqual {
    param(
        [AllowNull()][object] $Current,
        [AllowNull()][object] $Expected,
        [string] $Type = $null
    )

    if ($Type -eq 'DWord') {
        return (InitWin-ConvertDWordValue $Current) -eq (InitWin-ConvertDWordValue $Expected)
    }

    if (($Current -is [array]) -or ($Expected -is [array])) {
        if (($Current -isnot [array]) -or ($Expected -isnot [array])) { return $false }
        if ($Current.Count -ne $Expected.Count) { return $false }

        for ($i = 0; $i -lt $Current.Count; $i++) {
            if ($Current[$i] -cne $Expected[$i]) { return $false }
        }
        return $true
    }

    [string] $Current -ceq [string] $Expected
}

function InitWin-FormatValidationValue {
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) { return '<null>' }
    if ($Value -is [array]) { return ($Value -join ',') }
    [string] $Value
}

function InitWin-TestRegistryPropertiesDesired {
    param([Parameter(Mandatory)][object[]] $Properties)

    foreach ($property in $Properties) {
        $target = "$($property.Path)\$($property.Name)"
        if (-not (Test-Path -LiteralPath $property.Path)) {
            return InitWin-NewValidationResult `
                -Status Unset `
                -Target "registry: $target" `
                -Current '<missing path>' `
                -Expected (InitWin-FormatValidationValue $property.Value)
        }

        $item = Get-ItemProperty -LiteralPath $property.Path -ErrorAction Stop
        if ($item.PSObject.Properties.Name -notcontains $property.Name) {
            return InitWin-NewValidationResult `
                -Status Unset `
                -Target "registry: $target" `
                -Current '<missing>' `
                -Expected (InitWin-FormatValidationValue $property.Value)
        }

        $current = $item.PSObject.Properties[$property.Name].Value
        if (-not (InitWin-TestValueEqual -Current $current -Expected $property.Value -Type $property.Type)) {
            return InitWin-NewValidationResult `
                -Status Unset `
                -Target "registry: $target" `
                -Current (InitWin-FormatValidationValue $current) `
                -Expected (InitWin-FormatValidationValue $property.Value)
        }
    }

    InitWin-NewValidationResult -Status Desired
}

function InitWin-SetRegistryProperties {
    param([Parameter(Mandatory)][object[]] $Properties)

    foreach ($property in $Properties) {
        if (-not (Test-Path -LiteralPath $property.Path)) {
            New-Item -Path $property.Path -Force | Out-Null
        }
        $item = Get-ItemProperty -LiteralPath $property.Path -ErrorAction Stop
        if ($item.PSObject.Properties.Name -contains $property.Name) {
            $current = $item.PSObject.Properties[$property.Name].Value
            if (InitWin-TestValueEqual -Current $current -Expected $property.Value -Type $property.Type) {
                continue
            }
        }
        Set-ItemProperty -Path $property.Path -Name $property.Name -Type $property.Type -Value $property.Value
    }
}

function InitWin-TestPowerSettingZero {
    param(
        [Parameter(Mandatory)][string] $SubGroup,
        [Parameter(Mandatory)][string] $Setting
    )

    $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg query failed: $SubGroup $Setting"
    }

    $text = $output -join [Environment]::NewLine
    $acMatch = [regex]::Match($text, 'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)')
    $dcMatch = [regex]::Match($text, 'Current DC Power Setting Index:\s+0x([0-9a-fA-F]+)')
    if ((-not $acMatch.Success) -or (-not $dcMatch.Success)) {
        throw "Unexpected powercfg output: $SubGroup $Setting"
    }

    $acValue = [Convert]::ToUInt32($acMatch.Groups[1].Value, 16)
    $dcValue = [Convert]::ToUInt32($dcMatch.Groups[1].Value, 16)
    if (($acValue -eq 0) -and ($dcValue -eq 0)) {
        return InitWin-NewValidationResult -Status Desired
    }

    InitWin-NewValidationResult `
        -Status Unset `
        -Target "powercfg: SCHEME_CURRENT $SubGroup $Setting" `
        -Current "AC=$acValue DC=$dcValue" `
        -Expected 'AC=0 DC=0'
}
