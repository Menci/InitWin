function InitWin-TestExistingFilePath {
    param([AllowNull()][object] $Value)

    if ($Value -isnot [string]) { return $false }
    if ($Value -match '\r|\n') { return $false }
    try {
        $item = Get-Item -LiteralPath $Value -ErrorAction Stop
        -not $item.PSIsContainer
    } catch {
        $false
    }
}

function InitWin-ReadTextLines {
    param([Parameter(Mandatory)][string] $Path)

    @(Get-Content -LiteralPath $Path)
}

function InitWin-WriteValueDiff {
    param(
        [string] $Target = $null,
        [AllowNull()][object] $Current,
        [AllowNull()][object] $Expected
    )

    $currentText = InitWin-FormatValidationValue $Current
    $expectedText = InitWin-FormatValidationValue $Expected
    if (($currentText -notmatch '\r|\n') -and ($expectedText -notmatch '\r|\n')) {
        InitWin-WriteValueDiffLine -Target $Target -CurrentText $currentText -ExpectedText $expectedText
        return
    }

    if ($Target) { InitWin-WriteDetail $Target -ForegroundColor DarkCyan }
    InitWin-WriteDiffLine '--- current'
    InitWin-WriteDiffLine '+++ expected'
    foreach ($line in ($currentText -split '\r?\n')) {
        InitWin-WriteDiffLine "- $line"
    }
    foreach ($line in ($expectedText -split '\r?\n')) {
        InitWin-WriteDiffLine "+ $line"
    }
}

function InitWin-WriteValueDiffLine {
    param(
        [string] $Target = $null,
        [Parameter(Mandatory)][AllowEmptyString()][string] $CurrentText,
        [Parameter(Mandatory)][AllowEmptyString()][string] $ExpectedText
    )

    $segments = [System.Collections.Generic.List[object]]::new()
    if ($Target) {
        $segments.Add([pscustomobject]@{ Text = $Target; ForegroundColor = [ConsoleColor]::DarkCyan })
        $segments.Add([pscustomobject]@{ Text = ': '; ForegroundColor = [ConsoleColor]::Gray })
    }
    $segments.Add([pscustomobject]@{ Text = 'current '; ForegroundColor = [ConsoleColor]::Gray })
    $segments.Add([pscustomobject]@{ Text = InitWin-EscapeValidationValue $CurrentText; ForegroundColor = [ConsoleColor]::Red })
    $segments.Add([pscustomobject]@{ Text = ', expected '; ForegroundColor = [ConsoleColor]::Gray })
    $segments.Add([pscustomobject]@{ Text = InitWin-EscapeValidationValue $ExpectedText; ForegroundColor = [ConsoleColor]::Green })

    InitWin-WriteDetailSegments -Segments $segments
}

function InitWin-EscapeValidationValue {
    param([AllowNull()][string] $Value)

    if ($null -eq $Value) { return '"<null>"' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    '"' + $escaped + '"'
}

function InitWin-WriteSetDiff {
    param(
        [string] $Target = $null,
        [AllowNull()][object] $Current,
        [AllowNull()][object] $Expected
    )

    if ($Target) { InitWin-WriteDetail $Target -ForegroundColor DarkCyan }
    InitWin-WriteDiffLine '--- current'
    InitWin-WriteDiffLine '+++ expected'

    $currentSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in ((InitWin-FormatValidationValue $Current) -split '\r?\n')) {
        if ($line.Length -gt 0) { [void] $currentSet.Add($line) }
    }

    foreach ($line in ((InitWin-FormatValidationValue $Expected) -split '\r?\n')) {
        if (($line.Length -gt 0) -and (-not $currentSet.Contains($line))) {
            InitWin-WriteDiffLine "+ $line"
        }
    }
}

function InitWin-WriteLineDiff {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $CurrentLines,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $ExpectedLines
    )

    InitWin-WriteDiffLine '--- current'
    InitWin-WriteDiffLine '+++ expected'

    $m = $CurrentLines.Count
    $n = $ExpectedLines.Count
    $lengths = New-Object 'int[,]' ($m + 1),($n + 1)
    for ($i = $m - 1; $i -ge 0; $i--) {
        for ($j = $n - 1; $j -ge 0; $j--) {
            $nextI = $i + 1
            $nextJ = $j + 1
            if ($CurrentLines[$i] -ceq $ExpectedLines[$j]) {
                $lengths[$i,$j] = $lengths[$nextI,$nextJ] + 1
            } else {
                $downLength = $lengths[$nextI,$j]
                $rightLength = $lengths[$i,$nextJ]
                $lengths[$i,$j] = [Math]::Max($downLength, $rightLength)
            }
        }
    }

    $operations = [System.Collections.Generic.List[object]]::new()
    $currentIndex = 0
    $expectedIndex = 0
    while (($currentIndex -lt $m) -or ($expectedIndex -lt $n)) {
        if (($currentIndex -lt $m) -and ($expectedIndex -lt $n) -and ($CurrentLines[$currentIndex] -ceq $ExpectedLines[$expectedIndex])) {
            $operations.Add([pscustomobject]@{ Kind = ' '; Line = $CurrentLines[$currentIndex] })
            $currentIndex++
            $expectedIndex++
        } else {
            $nextCurrentIndex = $currentIndex + 1
            $nextExpectedIndex = $expectedIndex + 1
            $expectedAheadLength = if ($expectedIndex -lt $n) { $lengths[$currentIndex,$nextExpectedIndex] } else { 0 }
            $currentAheadLength = if ($currentIndex -lt $m) { $lengths[$nextCurrentIndex,$expectedIndex] } else { 0 }
            $shouldAddExpected = ($expectedIndex -lt $n) -and (($currentIndex -eq $m) -or ($expectedAheadLength -ge $currentAheadLength))
            if ($shouldAddExpected) {
                $operations.Add([pscustomobject]@{ Kind = '+'; Line = $ExpectedLines[$expectedIndex] })
                $expectedIndex++
            } else {
                $operations.Add([pscustomobject]@{ Kind = '-'; Line = $CurrentLines[$currentIndex] })
                $currentIndex++
            }
        }
    }

    $changeIndexes = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $operations.Count; $i++) {
        if ($operations[$i].Kind -ne ' ') { $changeIndexes.Add($i) }
    }
    if ($changeIndexes.Count -eq 0) { return }

    $context = 3
    $ranges = [System.Collections.Generic.List[object]]::new()
    foreach ($index in $changeIndexes) {
        $start = [Math]::Max(0, $index - $context)
        $end = [Math]::Min($operations.Count - 1, $index + $context)
        if (($ranges.Count -gt 0) -and ($start -le ($ranges[$ranges.Count - 1].End + 1))) {
            $ranges[$ranges.Count - 1].End = [Math]::Max($ranges[$ranges.Count - 1].End, $end)
        } else {
            $ranges.Add([pscustomobject]@{ Start = $start; End = $end })
        }
    }

    foreach ($range in $ranges) {
        InitWin-WriteDiffLine "@@ lines $($range.Start + 1)-$($range.End + 1) @@"
        for ($i = $range.Start; $i -le $range.End; $i++) {
            $operation = $operations[$i]
            InitWin-WriteDiffLine "$($operation.Kind) $($operation.Line)"
        }
    }
}

function InitWin-WriteFileDiff {
    param(
        [Parameter(Mandatory)][string] $CurrentPath,
        [Parameter(Mandatory)][string] $ExpectedPath
    )

    InitWin-WriteDetail "file: $CurrentPath" -ForegroundColor DarkCyan
    InitWin-WriteDetail "expected source: $ExpectedPath" -ForegroundColor DarkCyan
    $currentLines = @(InitWin-ReadTextLines $CurrentPath)
    $expectedLines = @(InitWin-ReadTextLines $ExpectedPath)
    InitWin-WriteLineDiff -CurrentLines $currentLines -ExpectedLines $expectedLines
}

function InitWin-WriteValidationDiff {
    param([Parameter(Mandatory)][object] $Validation)

    if (($null -ne $Validation.Current) -and ($null -ne $Validation.Expected)) {
        if ((InitWin-TestExistingFilePath $Validation.Current) -and (InitWin-TestExistingFilePath $Validation.Expected)) {
            InitWin-WriteFileDiff -CurrentPath $Validation.Current -ExpectedPath $Validation.Expected
        } elseif ($Validation.Diff -eq 'Set') {
            InitWin-WriteSetDiff -Target $Validation.Target -Current $Validation.Current -Expected $Validation.Expected
        } else {
            InitWin-WriteValueDiff -Target $Validation.Target -Current $Validation.Current -Expected $Validation.Expected
        }
    } elseif ($null -ne $Validation.Current) {
        InitWin-WriteValueDiff -Target $Validation.Target -Current $Validation.Current -Expected '<unset>'
    } elseif ($null -ne $Validation.Expected) {
        InitWin-WriteValueDiff -Target $Validation.Target -Current '<unset>' -Expected $Validation.Expected
    }

    if ($Validation.Reason) {
        InitWin-WriteDetail "reason: $($Validation.Reason)" -ForegroundColor Yellow
    }
}
