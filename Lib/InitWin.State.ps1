$script:InitWinEntries = [ordered]@{}
$script:InitWinPlannedEntries = [ordered]@{}
$script:InitWinIgnoredEntries = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:InitWinIgnoredEntryPatterns = [System.Collections.Generic.List[string]]::new()
$script:InitWinEntryIdPattern = '^(System|App|Packages)\.[A-Z][A-Za-z0-9]*\.[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)*$'
$script:InitWinEntryIdGlobPattern = '^(System|App|Packages)(\.([A-Z][A-Za-z0-9]*|\*))*$'
$script:InitWinWingetInstalledPackageIdsBySource = $null

function InitWin-ResetEntries {
    $script:InitWinEntries = [ordered]@{}
    $script:InitWinPlannedEntries = [ordered]@{}
    $script:InitWinIgnoredEntries = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $script:InitWinIgnoredEntryPatterns = [System.Collections.Generic.List[string]]::new()
    $script:InitWinWingetInstalledPackageIdsBySource = $null
}

function InitWin-NewValidationResult {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Desired', 'NotApplicable', 'Unset', 'Conflict')]
        [string] $Status,
        [string] $Target = $null,
        [object] $Current = $null,
        [object] $Expected = $null,
        [ValidateSet('Value', 'Set')]
        [string] $Diff = 'Value',
        [string] $Reason = $null
    )

    [pscustomobject]@{
        Status = $Status
        Target = $Target
        Current = $Current
        Expected = $Expected
        Diff = $Diff
        Reason = $Reason
    }
}

function InitWin-DefineEntry {
    param(
        [Parameter(Mandatory)]
        [string] $Id,
        [string] $Name = $null,
        [AllowNull()]
        [string] $Profile = $null,
        [scriptblock] $Validate = $null,
        [Parameter(Mandatory)]
        [scriptblock] $Apply
    )

    if ($Id -cnotmatch $script:InitWinEntryIdPattern) {
        throw "Entry id must be dot-qualified PascalCase, e.g. System.Section.EntryName, App.AppName.EntryName, or Packages.Source.EntryName: $Id"
    }
    if ($script:InitWinEntries.Contains($Id)) {
        throw "Duplicate entry id: $Id"
    }

    $script:InitWinEntries[$Id] = [pscustomobject]@{
        Id = $Id
        Name = $Name
        Profile = $Profile
        Validate = $Validate
        Apply = $Apply
    }
}

function InitWin-SetIgnoredEntries {
    param([string[]] $Ids = @())

    $script:InitWinIgnoredEntries = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $script:InitWinIgnoredEntryPatterns = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $Ids) {
        if ($id -like '*[*]*') {
            if ($id -cnotmatch $script:InitWinEntryIdGlobPattern) {
                throw "Ignored entry pattern must be dot-qualified PascalCase with * as whole segment, e.g. Packages.MicrosoftStore.*: $id"
            }
            if ($script:InitWinIgnoredEntryPatterns.Contains($id)) {
                throw "Duplicate ignored entry pattern: $id"
            }
            $script:InitWinIgnoredEntryPatterns.Add($id)
            continue
        }

        if ($id -cnotmatch $script:InitWinEntryIdPattern) {
            throw "Ignored entry id must be dot-qualified PascalCase, e.g. System.Section.EntryName, App.AppName.EntryName, or Packages.Source.EntryName: $id"
        }
        if (-not $script:InitWinIgnoredEntries.Add($id)) {
            throw "Duplicate ignored entry id: $id"
        }
    }
}

function InitWin-AssertIgnoredEntriesRegistered {
    foreach ($id in $script:InitWinIgnoredEntries) {
        if (-not $script:InitWinEntries.Contains($id)) {
            throw "Ignored entry is not registered: $id"
        }
    }
    foreach ($pattern in $script:InitWinIgnoredEntryPatterns) {
        $matched = $false
        foreach ($id in $script:InitWinEntries.Keys) {
            if ($id -like $pattern) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            throw "Ignored entry pattern does not match any registered entry: $pattern"
        }
    }
}

function InitWin-TestEntryIgnored {
    param([Parameter(Mandatory)][string] $Id)

    if ($script:InitWinIgnoredEntries.Contains($Id)) { return $true }
    foreach ($pattern in $script:InitWinIgnoredEntryPatterns) {
        if ($Id -like $pattern) { return $true }
    }
    $false
}
