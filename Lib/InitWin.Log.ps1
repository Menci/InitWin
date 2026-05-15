function InitWin-WritePhase {
    param([Parameter(Mandatory)][string] $Title)

    Write-Host ''
    InitWin-WriteLogLines -Prefix '┌─ ' -Message $Title -ForegroundColor Cyan
}

function InitWin-WriteStep {
    param([Parameter(Mandatory)][string] $Title)

    InitWin-WriteLogLines -Prefix '│  │  · ' -Message $Title -ForegroundColor DarkCyan
}

function InitWin-WritePhaseDetail {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,
        [ConsoleColor] $ForegroundColor = [ConsoleColor]::Gray
    )

    InitWin-WriteLogLines -Prefix '│  ' -Message $Message -ForegroundColor $ForegroundColor
}

function InitWin-WriteDetail {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,
        [ConsoleColor] $ForegroundColor = [ConsoleColor]::Gray
    )

    InitWin-WriteLogLines -Prefix '│  │    ' -Message $Message -ForegroundColor $ForegroundColor
}

function InitWin-WriteEntry {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $State,
        [string] $Summary = $null,
        [ConsoleColor] $ForegroundColor = [ConsoleColor]::Gray
    )

    $message = "$Id  [$State]"
    if ($Summary) { $message = "$message  $Summary" }
    InitWin-WriteLogLines -Prefix '│  ├─ ' -Message $message -ForegroundColor $ForegroundColor
}

function InitWin-WriteCommandOutput {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    InitWin-WriteLogLines -Prefix '│  │    │ ' -Message $Message -ForegroundColor DarkGray
}

function InitWin-WriteDiffLine {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line
    )

    $color = if ($Line -like '@@*') {
        [ConsoleColor]::Cyan
    } elseif ($Line -like '+*') {
        [ConsoleColor]::Green
    } elseif ($Line -like '-*') {
        [ConsoleColor]::Red
    } else {
        [ConsoleColor]::DarkGray
    }
    InitWin-WriteLogLines -Prefix '│  │    ' -Message $Line -ForegroundColor $color
}

function InitWin-WriteLogLines {
    param(
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,
        [ConsoleColor] $ForegroundColor = [ConsoleColor]::Gray
    )

    foreach ($line in ([string] $Message -split '\r?\n')) {
        Write-Host "$Prefix$line" -ForegroundColor $ForegroundColor
    }
}
