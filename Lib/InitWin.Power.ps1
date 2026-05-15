function InitWin-ConvertPowerTimeoutMinutesToSeconds {
    param([Parameter(Mandatory)][uint32] $Minutes)

    $Minutes * 60
}

function InitWin-TestPowerSettingValue {
    param(
        [Parameter(Mandatory)][string] $SubGroup,
        [Parameter(Mandatory)][string] $Setting,
        [Parameter(Mandatory)][uint32] $ExpectedAc,
        [Parameter(Mandatory)][uint32] $ExpectedDc
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
    if (($acValue -eq $ExpectedAc) -and ($dcValue -eq $ExpectedDc)) {
        return InitWin-NewValidationResult -Status Desired
    }

    InitWin-NewValidationResult `
        -Status Unset `
        -Target "powercfg: SCHEME_CURRENT $SubGroup $Setting" `
        -Current "AC=$acValue DC=$dcValue" `
        -Expected "AC=$ExpectedAc DC=$ExpectedDc"
}
