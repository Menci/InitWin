# InitWin.Core.ps1
# Ordered loader for InitWin library modules.

. (Join-Path $PSScriptRoot 'InitWin.State.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Log.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Diff.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Native.ps1')
. (Join-Path $PSScriptRoot 'InitWin.PowerShell.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Registry.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Packages.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Entry.ps1')
. (Join-Path $PSScriptRoot 'InitWin.Files.ps1')
