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

function InitWin-ReadIniDocument {
    param([Parameter(Mandatory)][string] $Path)

    $sections = [ordered]@{}
    $currentSection = ''
    $sections[$currentSection] = [ordered]@{}
    $lineNumber = 0

    foreach ($line in (InitWin-ReadTextLines $Path)) {
        $lineNumber++
        if (($line -match '^\s*$') -or ($line -match '^\s*[;#]')) { continue }

        $sectionMatch = [regex]::Match($line, '^\s*\[(.+)\]\s*$')
        if ($sectionMatch.Success) {
            $currentSection = $sectionMatch.Groups[1].Value.Trim()
            if (-not $sections.Contains($currentSection)) {
                $sections[$currentSection] = [ordered]@{}
            }
            continue
        }

        $keyMatch = [regex]::Match($line, '^\s*([^=]+?)\s*=(.*)$')
        if (-not $keyMatch.Success) {
            throw "Invalid INI line in $Path at line $lineNumber`: $line"
        }

        $key = $keyMatch.Groups[1].Value.Trim()
        if ($key.Length -eq 0) {
            throw "Invalid empty INI key in $Path at line $lineNumber"
        }

        $sections[$currentSection][$key] = $keyMatch.Groups[2].Value.Trim()
    }

    $sections
}

function InitWin-GetIniEntryValue {
    param(
        [Parameter(Mandatory)][object] $Document,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Section,
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][ref] $Found
    )

    if (($Document.Contains($Section)) -and ($Document[$Section].Contains($Key))) {
        $Found.Value = $true
        return $Document[$Section][$Key]
    }

    $Found.Value = $false
    $null
}

function InitWin-TestIniEntriesDesired {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        return InitWin-NewValidationResult `
            -Status Unset `
            -Target "file: $Destination" `
            -Current '<missing>' `
            -Expected "copy entries from $Source"
    }

    $sourceDocument = InitWin-ReadIniDocument -Path $Source
    try {
        $destinationDocument = InitWin-ReadIniDocument -Path $Destination
    } catch {
        return InitWin-NewValidationResult `
            -Status Conflict `
            -Target "file: $Destination" `
            -Current '<invalid INI>' `
            -Expected "parseable INI containing entries from $Source" `
            -Reason $_.Exception.Message
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($section in $sourceDocument.Keys) {
        foreach ($key in $sourceDocument[$section].Keys) {
            $found = $false
            $current = InitWin-GetIniEntryValue -Document $destinationDocument -Section $section -Key $key -Found ([ref] $found)
            $expected = $sourceDocument[$section][$key]
            if ((-not $found) -or ($current -cne $expected)) {
                $sectionName = if ($section.Length -gt 0) { "[$section] " } else { '' }
                $results.Add((InitWin-NewValidationResult `
                    -Status Unset `
                    -Target "ini: $Destination $sectionName$key" `
                    -Current $(if ($found) { $current } else { '<missing>' }) `
                    -Expected $expected))
            }
        }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
}

function InitWin-SetIniEntries {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        InitWin-CopyFile -Source $Source -Destination $Destination
        return
    }

    $sourceDocument = InitWin-ReadIniDocument -Path $Source
    $pending = [ordered]@{}
    foreach ($section in $sourceDocument.Keys) {
        if ($sourceDocument[$section].Count -gt 0) {
            $pending[$section] = [ordered]@{}
            foreach ($key in $sourceDocument[$section].Keys) {
                $pending[$section][$key] = $sourceDocument[$section][$key]
            }
        }
    }

    $existingLines = @(InitWin-ReadTextLines $Destination)
    $newLines = [System.Collections.Generic.List[string]]::new()
    $currentSection = ''

    $appendPendingSectionEntries = {
        param([Parameter(Mandatory)][AllowEmptyString()][string] $Section)

        if (-not $pending.Contains($Section)) { return }
        foreach ($key in @($pending[$Section].Keys)) {
            $newLines.Add("$key=$($pending[$Section][$key])")
            $pending[$Section].Remove($key)
        }
    }

    foreach ($line in $existingLines) {
        $sectionMatch = [regex]::Match($line, '^\s*\[(.+)\]\s*$')
        if ($sectionMatch.Success) {
            & $appendPendingSectionEntries $currentSection
            $currentSection = $sectionMatch.Groups[1].Value.Trim()
            $newLines.Add($line)
            continue
        }

        $keyMatch = [regex]::Match($line, '^\s*([^=]+?)\s*=')
        if ($keyMatch.Success -and $pending.Contains($currentSection)) {
            $key = $keyMatch.Groups[1].Value.Trim()
            if ($pending[$currentSection].Contains($key)) {
                $newLines.Add("$key=$($pending[$currentSection][$key])")
                $pending[$currentSection].Remove($key)
                continue
            }
        }

        $newLines.Add($line)
    }

    & $appendPendingSectionEntries $currentSection
    foreach ($section in $pending.Keys) {
        if ($pending[$section].Count -eq 0) { continue }
        if (($newLines.Count -gt 0) -and ($newLines[$newLines.Count - 1].Length -gt 0)) {
            $newLines.Add('')
        }
        if ($section.Length -gt 0) {
            $newLines.Add("[$section]")
        }
        foreach ($key in $pending[$section].Keys) {
            $newLines.Add("$key=$($pending[$section][$key])")
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    [IO.File]::WriteAllText($Destination, (($newLines -join [Environment]::NewLine) + [Environment]::NewLine))
}

function InitWin-TestDirectoryFilesDesired {
    param(
        [Parameter(Mandatory)][string] $SourceDirectory,
        [Parameter(Mandatory)][string] $DestinationDirectory,
        [string[]] $ExcludeNames = @('Entries.ps1', 'AGENTS.md')
    )

    $sourceFiles = Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File |
        Where-Object { $_.Name -notin $ExcludeNames }
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $sourceFiles) {
        $relative = $file.FullName.Substring($SourceDirectory.Length + 1)
        $target = Join-Path $DestinationDirectory $relative
        if (-not (Test-Path -LiteralPath $target)) {
            $results.Add((InitWin-NewValidationResult `
                -Status Unset `
                -Target "file: $target" `
                -Current '<missing>' `
                -Expected "copy from $($file.FullName)"))
            continue
        }
        if (-not (InitWin-TestFileContentEqual -Source $file.FullName -Destination $target)) {
            $results.Add((InitWin-NewValidationResult `
                -Status Unset `
                -Target "file: $target" `
                -Current $target `
                -Expected $file.FullName))
        }
    }

    if ($results.Count -gt 0) { return $results }
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
        return InitWin-NewValidationResult -Status Unset -Target "file: $Destination" -Current $Destination -Expected $Source
    }
    InitWin-NewValidationResult -Status Desired
}
