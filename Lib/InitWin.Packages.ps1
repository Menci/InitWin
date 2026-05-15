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
