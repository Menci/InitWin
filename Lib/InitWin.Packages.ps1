function InitWin-GetWingetInstalledPackageIdsBySource {
    param([Parameter(Mandatory)][ValidateSet('winget', 'msstore')][string] $Source)

    if ($null -eq $script:InitWinWingetInstalledPackageIdsBySource) {
        $script:InitWinWingetInstalledPackageIdsBySource = [ordered]@{}
    }
    if ($script:InitWinWingetInstalledPackageIdsBySource.Contains($Source)) {
        return $script:InitWinWingetInstalledPackageIdsBySource[$Source]
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $exportPath = Join-Path $env:TEMP "InitWin-winget-$Source-$PID.json"

    try {
        if (Test-Path -LiteralPath $exportPath) {
            Remove-Item -LiteralPath $exportPath -Force
        }

        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = winget export --source $Source --output $exportPath --accept-source-agreements --disable-interactivity 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($exitCode -ne 0) {
            throw "winget export failed with exit code $exitCode`: $($output -join [Environment]::NewLine)"
        }

        if (Test-Path -LiteralPath $exportPath) {
            $export = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
            foreach ($sourceEntry in @($export.Sources)) {
                if ($sourceEntry.SourceDetails.Name -ne $Source) { continue }
                foreach ($package in @($sourceEntry.Packages)) {
                    if ($package.PackageIdentifier) {
                        [void] $ids.Add([string] $package.PackageIdentifier)
                    }
                }
            }
        }
    } finally {
        Remove-Item -LiteralPath $exportPath -Force -ErrorAction SilentlyContinue
    }

    $script:InitWinWingetInstalledPackageIdsBySource[$Source] = $ids
    $ids
}

function InitWin-TestWingetPackageInstalled {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][ValidateSet('winget', 'msstore')][string] $Source
    )

    $ids = InitWin-GetWingetInstalledPackageIdsBySource -Source $Source
    $ids.Contains($Id)
}

function InitWin-GetUninstallDisplayNames {
    if ($null -ne $script:InitWinUninstallDisplayNames) {
        return $script:InitWinUninstallDisplayNames
    }

    $displayNames = [System.Collections.Generic.List[string]]::new()
    $uninstallRoots = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
            ForEach-Object {
                $displayName = (Get-ItemProperty -LiteralPath $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                if ($displayName) { $displayNames.Add([string] $displayName) }
            }
    }

    $script:InitWinUninstallDisplayNames = $displayNames
    $displayNames
}

function InitWin-TestUninstallDisplayNameInstalled {
    param([Parameter(Mandatory)][string] $Pattern)

    foreach ($displayName in (InitWin-GetUninstallDisplayNames)) {
        if ($displayName -like $Pattern) { return $true }
    }
    $false
}

function InitWin-TestCommandAvailable {
    param([Parameter(Mandatory)][string] $Name)

    $null -ne (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function InitWin-TestPackageInstalled {
    param(
        [string[]] $AppxPackageNames = @(),
        [string[]] $WingetPackageIds = @(),
        [string[]] $MsStorePackageIds = @(),
        [string[]] $CommandNames = @(),
        [string[]] $UninstallDisplayNamePatterns = @()
    )

    foreach ($appxPackageName in $AppxPackageNames) {
        if (Get-AppxPackage -Name $appxPackageName -ErrorAction SilentlyContinue) { return $true }
    }

    foreach ($wingetPackageId in $WingetPackageIds) {
        if (InitWin-TestWingetPackageInstalled -Id $wingetPackageId -Source winget) { return $true }
    }

    foreach ($msStorePackageId in $MsStorePackageIds) {
        if (InitWin-TestWingetPackageInstalled -Id $msStorePackageId -Source msstore) { return $true }
    }

    foreach ($commandName in $CommandNames) {
        if (InitWin-TestCommandAvailable -Name $commandName) { return $true }
    }

    foreach ($pattern in $UninstallDisplayNamePatterns) {
        if (InitWin-TestUninstallDisplayNameInstalled -Pattern $pattern) { return $true }
    }

    $false
}

function InitWin-InstallWingetPackage {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][ValidateSet('winget', 'msstore')][string] $Source
    )

    if (InitWin-TestWingetPackageInstalled -Id $Id -Source $Source) {
        InitWin-WriteDetail "already installed: $Name ($Id)"
        return
    }

    InitWin-WriteDetail "$Source`: $Name ($Id)"
    InitWin-InvokeNative -FilePath winget -Arguments @(
        'install'
        '--id'
        $Id
        '--source'
        $Source
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
        '--silent'
    )

    if (($null -ne $script:InitWinWingetInstalledPackageIdsBySource) -and $script:InitWinWingetInstalledPackageIdsBySource.Contains($Source)) {
        [void] $script:InitWinWingetInstalledPackageIdsBySource[$Source].Add($Id)
    }
}
