function InitWin-TestFileContentEqual {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) { return $false }
    $sourceHash = Get-FileHash -LiteralPath $Source -Algorithm SHA256
    $destinationHash = Get-FileHash -LiteralPath $Destination -Algorithm SHA256
    if ($sourceHash.Hash -eq $destinationHash.Hash) { return $true }

    try {
        $sourceLines = InitWin-ReadTextLines $Source
        $destinationLines = InitWin-ReadTextLines $Destination
    } catch {
        return $false
    }

    if ($sourceLines.Count -ne $destinationLines.Count) { return $false }
    for ($i = 0; $i -lt $sourceLines.Count; $i++) {
        if ($sourceLines[$i] -cne $destinationLines[$i]) { return $false }
    }
    $true
}

function InitWin-ImportPowerShellDataFile {
    param([Parameter(Mandatory)][string] $Path)

    if (Get-Command -Name Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
        return Import-PowerShellDataFile -LiteralPath $Path
    }

    $data = $null
    Import-LocalizedData `
        -BaseDirectory (Split-Path -Parent $Path) `
        -FileName (Split-Path -Leaf $Path) `
        -BindingVariable data
    $data
}

function InitWin-CopyFile {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function InitWin-CopyDirectoryFiles {
    param(
        [Parameter(Mandatory)][string] $SourceDirectory,
        [Parameter(Mandatory)][string] $DestinationDirectory,
        [string[]] $ExcludeNames = @('Entries.ps1', 'AGENTS.md')
    )

    Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File |
        Where-Object { $_.Name -notin $ExcludeNames } |
        ForEach-Object {
            $relative = $_.FullName.Substring($SourceDirectory.Length + 1)
            $target = Join-Path $DestinationDirectory $relative
            InitWin-CopyFile -Source $_.FullName -Destination $target
            InitWin-WriteDetail $relative
        }
}

function InitWin-TestDirectoryFilesDesired {
    param(
        [Parameter(Mandatory)][string] $SourceDirectory,
        [Parameter(Mandatory)][string] $DestinationDirectory,
        [string[]] $ExcludeNames = @('Entries.ps1', 'AGENTS.md')
    )

    $sourceFiles = Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File |
        Where-Object { $_.Name -notin $ExcludeNames }
    foreach ($file in $sourceFiles) {
        $relative = $file.FullName.Substring($SourceDirectory.Length + 1)
        $target = Join-Path $DestinationDirectory $relative
        if (-not (Test-Path -LiteralPath $target)) {
            return InitWin-NewValidationResult `
                -Status Unset `
                -Target "file: $target" `
                -Current '<missing>' `
                -Expected "copy from $($file.FullName)"
        }
        if (-not (InitWin-TestFileContentEqual -Source $file.FullName -Destination $target)) {
            return InitWin-NewValidationResult `
                -Status Conflict `
                -Target "file: $target" `
                -Current $target `
                -Expected $file.FullName
        }
    }

    InitWin-NewValidationResult -Status Desired
}

function InitWin-TestSingleFileDesired {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        return InitWin-NewValidationResult `
            -Status Unset `
            -Target "file: $Destination" `
            -Current '<missing>' `
            -Expected "copy from $Source"
    }
    if (-not (InitWin-TestFileContentEqual -Source $Source -Destination $Destination)) {
        return InitWin-NewValidationResult -Status Conflict -Target "file: $Destination" -Current $Destination -Expected $Source
    }
    InitWin-NewValidationResult -Status Desired
}
