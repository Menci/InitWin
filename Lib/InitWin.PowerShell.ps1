$script:InitWinPowerShellCoreExecutionPolicyKey = 'Microsoft.PowerShell:ExecutionPolicy'

function InitWin-QuotePowerShellString {
    param([Parameter(Mandatory)][string] $Value)

    "'$($Value.Replace("'", "''"))'"
}

function InitWin-QuotePowerShellStringArray {
    param([string[]] $Values = @())

    $items = @($Values | ForEach-Object { InitWin-QuotePowerShellString $_ })
    '@(' + ($items -join ', ') + ')'
}

function InitWin-InvokeWindowsPowerShell {
    param(
        [Parameter(Mandatory)][string] $Script,
        [switch] $CaptureOutput
    )

    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $output = & powershell.exe `
        -NoLogo `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -EncodedCommand $encodedCommand 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "powershell.exe failed with exit code $exitCode`: $($output -join [Environment]::NewLine)"
    }

    if ($CaptureOutput) { return $output }
}

function InitWin-InvokeWindowsPowerShellJson {
    param([Parameter(Mandatory)][string] $Script)

    $output = @(InitWin-InvokeWindowsPowerShell -Script $Script -CaptureOutput)
    $raw = ($output | Where-Object { $null -ne $_ } | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
    if ($raw.Trim().Length -eq 0) { return $null }
    $raw | ConvertFrom-Json
}

function InitWin-InvokeWindowsPowerShellAsSystem {
    param(
        [Parameter(Mandatory)][string] $Script,
        [int] $TimeoutSeconds = 300
    )

    $taskId = "InitWin-$PID-$([Guid]::NewGuid().ToString('N'))"
    $taskPath = '\InitWin\'
    $workRoot = Join-Path $env:ProgramData 'InitWin\ScheduledTasks'
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

    $scriptPath = Join-Path $workRoot "$taskId.ps1"
    $resultPath = Join-Path $workRoot "$taskId.ok"
    $errorPath = Join-Path $workRoot "$taskId.err"

    $payloadLiteral = InitWin-QuotePowerShellString $Script
    $resultPathLiteral = InitWin-QuotePowerShellString $resultPath
    $errorPathLiteral = InitWin-QuotePowerShellString $errorPath
    $wrapper = @"
`$ErrorActionPreference = 'Stop'
try {
    `$payload = $payloadLiteral
    `$scriptBlock = [scriptblock]::Create(`$payload)
    & `$scriptBlock
    [IO.File]::WriteAllText($resultPathLiteral, 'OK')
} catch {
    [IO.File]::WriteAllText($errorPathLiteral, (`$_ | Out-String))
    exit 1
}
"@

    [IO.File]::WriteAllText($scriptPath, $wrapper, [Text.UTF8Encoding]::new($true))

    $task = $null
    try {
        $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = InitWin-JoinNativeArguments -Arguments @(
            '-NoLogo'
            '-NoProfile'
            '-NonInteractive'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $scriptPath
        )
        $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Seconds $TimeoutSeconds)

        $task = Register-ScheduledTask `
            -TaskName $taskId `
            -TaskPath $taskPath `
            -Action $action `
            -Principal $principal `
            -Settings $settings `
            -Force

        $startedAt = [DateTime]::Now
        Start-ScheduledTask -InputObject $task

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ((-not (Test-Path -LiteralPath $resultPath)) -and (-not (Test-Path -LiteralPath $errorPath))) {
            if ([DateTime]::UtcNow -gt $deadline) {
                throw "Timed out waiting for SYSTEM task: $taskPath$taskId"
            }

            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskId -TaskPath $taskPath -ErrorAction SilentlyContinue
            $taskState = (Get-ScheduledTask -TaskName $taskId -TaskPath $taskPath -ErrorAction SilentlyContinue).State
            if ($taskInfo -and ($taskInfo.LastRunTime -ge $startedAt.AddSeconds(-1)) -and ($taskState -and ([string] $taskState) -ne 'Running')) {
                throw "SYSTEM task exited without writing a result marker: $taskPath$taskId LastTaskResult=$($taskInfo.LastTaskResult)"
            }

            Start-Sleep -Milliseconds 250
        }

        if (Test-Path -LiteralPath $errorPath) {
            $message = Get-Content -LiteralPath $errorPath -Raw
            throw "SYSTEM task failed: $message"
        }
    } finally {
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskId -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $scriptPath,$resultPath,$errorPath -Force -ErrorAction SilentlyContinue
    }
}

function InitWin-GetPowerShellCoreCurrentUserConfigPath {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\powershell.config.json'
}

function InitWin-AddPowerShellCoreHomePath {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]] $Paths,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]] $Seen,
        [AllowNull()][string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    $resolvedPath = [Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) { return }
    if ($Seen.Add($resolvedPath)) {
        $Paths.Add($resolvedPath)
    }
}

function InitWin-GetPowerShellCoreHomePaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $installedVersionRoots = @(
        'HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\PowerShellCore\InstalledVersions'
    )
    foreach ($root in $installedVersionRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $installLocation = (Get-ItemProperty -LiteralPath $_.PSPath -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
            InitWin-AddPowerShellCoreHomePath -Paths $paths -Seen $seen -Path $installLocation
        }
    }

    foreach ($package in @(Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue)) {
        InitWin-AddPowerShellCoreHomePath -Paths $paths -Seen $seen -Path $package.InstallLocation
    }

    foreach ($relativePath in @('PowerShell\7', 'PowerShell\7-preview')) {
        InitWin-AddPowerShellCoreHomePath -Paths $paths -Seen $seen -Path (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) $relativePath)
    }

    foreach ($command in @(Get-Command -Name pwsh.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        $homePath = Split-Path -Parent $command.Source
        if (Test-Path -LiteralPath (Join-Path $homePath 'System.Management.Automation.dll')) {
            InitWin-AddPowerShellCoreHomePath -Paths $paths -Seen $seen -Path $homePath
        }
    }

    $paths
}

function InitWin-GetPowerShellCoreConfigTargets {
    [pscustomobject]@{
        Scope = 'CurrentUser'
        Path = InitWin-GetPowerShellCoreCurrentUserConfigPath
    }

    foreach ($homePath in (InitWin-GetPowerShellCoreHomePaths)) {
        [pscustomobject]@{
            Scope = 'LocalMachine'
            Path = Join-Path $homePath 'powershell.config.json'
        }
    }
}

function InitWin-ReadPowerShellConfigJson {
    param([Parameter(Mandatory)][string] $Path)

    $config = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $config }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw.Trim().Length -eq 0) { return $config }

    $parsed = $raw | ConvertFrom-Json
    foreach ($property in $parsed.PSObject.Properties) {
        $config[$property.Name] = $property.Value
    }
    $config
}

function InitWin-TestPowerShellCoreConfigExecutionPolicy {
    param(
        [Parameter(Mandatory)][psobject] $ConfigTarget,
        [Parameter(Mandatory)][string] $Expected
    )

    $configPath = $ConfigTarget.Path
    $target = "PowerShell $($ConfigTarget.Scope) config: $configPath\$script:InitWinPowerShellCoreExecutionPolicyKey"
    if (-not (Test-Path -LiteralPath $configPath)) {
        return InitWin-NewValidationResult -Status Unset -Target $target -Current '<missing file>' -Expected $Expected
    }

    try {
        $config = InitWin-ReadPowerShellConfigJson -Path $configPath
    } catch {
        return InitWin-NewValidationResult -Status Conflict -Target $target -Current '<invalid json>' -Expected $Expected -Reason $_.Exception.Message
    }

    if (-not $config.Contains($script:InitWinPowerShellCoreExecutionPolicyKey)) {
        return InitWin-NewValidationResult -Status Unset -Target $target -Current '<missing>' -Expected $Expected
    }

    $current = [string] $config[$script:InitWinPowerShellCoreExecutionPolicyKey]
    if ($current -ne $Expected) {
        return InitWin-NewValidationResult -Status Unset -Target $target -Current $current -Expected $Expected
    }

    InitWin-NewValidationResult -Status Desired
}

function InitWin-TestPowerShellCoreExecutionPolicy {
    param([Parameter(Mandatory)][string] $Expected)

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($configTarget in @(InitWin-GetPowerShellCoreConfigTargets)) {
        $result = InitWin-TestPowerShellCoreConfigExecutionPolicy -ConfigTarget $configTarget -Expected $Expected
        if ($result.Status -ne 'Desired') { $results.Add($result) }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
}

function InitWin-SetPowerShellCoreConfigExecutionPolicy {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Policy
    )

    $config = InitWin-ReadPowerShellConfigJson -Path $Path
    $config[$script:InitWinPowerShellCoreExecutionPolicyKey] = $Policy

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $json = $config | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine)
}

function InitWin-SetPowerShellCoreConfigExecutionPolicyAsSystem {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Policy
    )

    $pathLiteral = InitWin-QuotePowerShellString $Path
    $policyLiteral = InitWin-QuotePowerShellString $Policy
    $keyLiteral = InitWin-QuotePowerShellString $script:InitWinPowerShellCoreExecutionPolicyKey
    $script = @"
`$path = $pathLiteral
`$policy = $policyLiteral
`$key = $keyLiteral
`$config = [ordered]@{}
if (Test-Path -LiteralPath `$path) {
    `$raw = Get-Content -LiteralPath `$path -Raw
    if (`$raw.Trim().Length -gt 0) {
        `$parsed = `$raw | ConvertFrom-Json
        foreach (`$property in `$parsed.PSObject.Properties) {
            `$config[`$property.Name] = `$property.Value
        }
    }
}
`$config[`$key] = `$policy
New-Item -ItemType Directory -Force -Path (Split-Path -Parent `$path) | Out-Null
`$json = `$config | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText(`$path, `$json + [Environment]::NewLine)
"@
    InitWin-InvokeWindowsPowerShellAsSystem -Script $script
}

function InitWin-SetPowerShellCoreExecutionPolicy {
    param([Parameter(Mandatory)][string] $Policy)

    foreach ($configTarget in @(InitWin-GetPowerShellCoreConfigTargets)) {
        if ($configTarget.Scope -eq 'LocalMachine') {
            InitWin-SetPowerShellCoreConfigExecutionPolicyAsSystem -Path $configTarget.Path -Policy $Policy
        } else {
            InitWin-SetPowerShellCoreConfigExecutionPolicy -Path $configTarget.Path -Policy $Policy
        }
    }
}
