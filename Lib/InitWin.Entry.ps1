function InitWin-NormalizeValidationResult {
    param([object] $Result)

    if ($null -eq $Result) {
        return InitWin-NewValidationResult -Status Unset
    }
    if ($Result -is [string]) {
        return InitWin-NewValidationResult -Status $Result
    }
    if ($Result -is [hashtable]) {
        return InitWin-NewValidationResult `
            -Status $Result.Status `
            -Target $Result.Target `
            -Current $Result.Current `
            -Expected $Result.Expected `
            -Diff $Result.Diff `
            -Reason $Result.Reason
    }
    if ($Result.PSObject.Properties.Name -contains 'Status') {
        return InitWin-NewValidationResult `
            -Status $Result.Status `
            -Target $Result.Target `
            -Current $Result.Current `
            -Expected $Result.Expected `
            -Diff $Result.Diff `
            -Reason $Result.Reason
    }

    throw "Unsupported validation result: $Result"
}

function InitWin-AssertEntryPlanComplete {
    foreach ($id in $script:InitWinEntries.Keys) {
        if (-not $script:InitWinPlannedEntries.Contains($id)) {
            throw "Registered entry is missing from execution plan: $id"
        }
    }
}

function InitWin-InvokeEntry {
    param(
        [Parameter(Mandatory)][string] $Id,
        [AllowNull()][string] $Profile = $null,
        [object] $Applied = $null,
        [switch] $DryRun
    )

    if ($Applied) { $Applied.Value = $false }

    if (-not $script:InitWinEntries.Contains($Id)) {
        throw "Unknown entry id: $Id"
    }

    $entry = $script:InitWinEntries[$Id]
    if (InitWin-TestEntryIgnored -Id $entry.Id) {
        InitWin-WriteEntry -Id $entry.Id -State 'ignored' -ForegroundColor DarkGray
        return
    }

    if ($entry.Profile -and ($entry.Profile -ne $Profile)) {
        InitWin-WriteEntry -Id $entry.Id -State "skip profile=$($entry.Profile)"
        return
    }

    $validation = if ($entry.Validate) {
        InitWin-NormalizeValidationResult (& $entry.Validate)
    } else {
        InitWin-NewValidationResult -Status Unset
    }

    if ($validation.Status -eq 'Desired') {
        InitWin-WriteEntry -Id $entry.Id -State 'desired'
        return
    }

    if ($validation.Status -eq 'NotApplicable') {
        InitWin-WriteEntry -Id $entry.Id -State 'not applicable'
        InitWin-WriteValidationDiff -Validation $validation
        return
    }

    if (($validation.Status -eq 'Unset') -and $DryRun) {
        $summary = InitWin-GetValidationDiffSummary -Validation $validation
        InitWin-WriteEntry -Id $entry.Id -State 'would apply' -Summary $summary -ForegroundColor DarkGreen
        if (-not $summary) {
            InitWin-WriteValidationDiff -Validation $validation
        }
        return
    }

    if ($validation.Status -eq 'Conflict') {
        InitWin-WriteEntry -Id $entry.Id -State 'conflict' -ForegroundColor Yellow
        InitWin-WriteValidationDiff -Validation $validation
        if ($DryRun) { return }

        $answer = Read-Host 'Apply anyway? [y/N]'
        if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
            InitWin-WriteEntry -Id $entry.Id -State 'not applied'
            return
        }
    }

    InitWin-WriteEntry -Id $entry.Id -State 'apply' -ForegroundColor Green
    & $entry.Apply
    if ($Applied) { $Applied.Value = $true }
}

function InitWin-InvokeEntries {
    param(
        [Parameter(Mandatory)][string[]] $Ids,
        [AllowNull()][string] $Profile = $null,
        [switch] $DryRun
    )

    foreach ($id in $Ids) {
        if (-not $script:InitWinEntries.Contains($id)) {
            throw "Unknown entry id in execution plan: $id"
        }
        if ($script:InitWinPlannedEntries.Contains($id)) {
            throw "Duplicate entry id in execution plan: $id"
        }
        $script:InitWinPlannedEntries[$id] = $true
    }

    foreach ($id in $Ids) {
        $applied = $false
        InitWin-InvokeEntry -Id $id -Profile $Profile -Applied ([ref] $applied) -DryRun:$DryRun
    }
}
