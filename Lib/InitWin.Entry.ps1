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

function InitWin-NormalizeValidationResults {
    param([AllowNull()][object] $Result)

    if ($null -eq $Result) {
        return InitWin-NewValidationResult -Status Unset
    }

    $isSingleResult =
        ($Result -is [string]) -or
        ($Result -is [hashtable]) -or
        (($Result.PSObject.Properties.Name -contains 'Status') -and ($Result -isnot [array]))

    $items = if ($isSingleResult) { @($Result) } else { @($Result) }
    $validations = @($items | ForEach-Object { InitWin-NormalizeValidationResult $_ })
    if ($validations.Count -eq 0) {
        return InitWin-NewValidationResult -Status Desired
    }

    if ($validations.Count -gt 1) {
        $validations = @($validations | Where-Object { $_.Status -ne 'Desired' })
        if ($validations.Count -eq 0) {
            return InitWin-NewValidationResult -Status Desired
        }
    }

    $validations
}

function InitWin-GetValidationState {
    param([Parameter(Mandatory)][object[]] $Validations)

    $statuses = @($Validations | ForEach-Object { $_.Status })
    if ($statuses -contains 'Conflict') { return 'Conflict' }
    if ($statuses -contains 'Unset') { return 'Unset' }
    if ($statuses -contains 'NotApplicable') { return 'NotApplicable' }
    'Desired'
}

function InitWin-TestValidationResultsDesired {
    param([AllowNull()][object] $Result)

    $validations = @(InitWin-NormalizeValidationResults -Result $Result)
    ($validations.Count -eq 1) -and ($validations[0].Status -eq 'Desired')
}

function InitWin-WriteValidationDiffs {
    param([Parameter(Mandatory)][object[]] $Validations)

    foreach ($validation in $Validations) {
        if ($validation.Status -ne 'Desired') {
            InitWin-WriteValidationDiff -Validation $validation
        }
    }
}

function InitWin-GetEntryDisplayName {
    param([Parameter(Mandatory)][object] $Entry)

    if ($Entry.PSObject.Properties.Name -contains 'Name') {
        if (-not [string]::IsNullOrWhiteSpace($Entry.Name)) { return $Entry.Name }
    }
    $Entry.Id
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

    if (-not (InitWin-TestEntryProfileMatch -Entry $entry -Profile $Profile)) {
        InitWin-WriteEntry -Id $entry.Id -State "skip profile=$Profile"
        return
    }

    $validations = if ($entry.Validate) {
        $rawValidation = & $entry.Validate
        @(InitWin-NormalizeValidationResults -Result $rawValidation)
    } else {
        @(InitWin-NewValidationResult -Status Unset)
    }
    $validationState = InitWin-GetValidationState -Validations $validations

    if ($validationState -eq 'Desired') {
        InitWin-WriteEntry -Id $entry.Id -State 'desired'
        return
    }

    if ($validationState -eq 'NotApplicable') {
        InitWin-WriteEntry -Id $entry.Id -State 'not applicable'
        InitWin-WriteValidationDiffs -Validations $validations
        return
    }

    if (($validationState -eq 'Unset') -and $DryRun) {
        InitWin-WriteEntry -Id $entry.Id -State 'would apply' -ForegroundColor DarkGreen
        InitWin-WriteValidationDiffs -Validations $validations
        return
    }

    if ($validationState -eq 'Conflict') {
        InitWin-WriteEntry -Id $entry.Id -State 'conflict' -ForegroundColor Yellow
        InitWin-WriteValidationDiffs -Validations $validations
        if ($DryRun) { return }

        $answer = Read-Host 'Apply anyway? [y/N]'
        if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
            InitWin-WriteEntry -Id $entry.Id -State 'not applied'
            return
        }
    }

    InitWin-WriteEntry -Id $entry.Id -State 'apply' -ForegroundColor Green
    InitWin-WriteStep (InitWin-GetEntryDisplayName -Entry $entry)
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
