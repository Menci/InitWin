InitWin-DefineEntry -Id Packages.Fonts.MapleMono -Name 'Maple Mono NF CN 字体' -Validate {
    $mapleRegistryPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    $mapleAlreadyInstalled = foreach ($mapleReg in $mapleRegistryPaths) {
        Get-ItemProperty -Path $mapleReg -ErrorAction SilentlyContinue |
            ForEach-Object { $_.PSObject.Properties } |
            Where-Object {
                ($_.Name -like 'Maple Mono NF CN*') -or
                ($_.Name -like 'MapleMono-NF-CN*') -or
                ([IO.Path]::GetFileName([string] $_.Value) -like 'MapleMono-NF-CN*')
            }
    }

    if ($mapleAlreadyInstalled) { return InitWin-NewValidationResult -Status Desired }
    InitWin-NewValidationResult -Status Unset -Target 'font: Maple Mono NF CN' -Current '<missing>' -Expected 'installed'
} -Apply {
    # 来源：https://github.com/subframe7536/maple-font
    $mapleZip = Join-Path $env:TEMP 'MapleMono-NF-CN.zip'
    $mapleDst = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $mapleReg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $mapleUrl = 'https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-CN.zip'

    New-Item -ItemType Directory -Force -Path $mapleDst | Out-Null
    $mapleTmp = Join-Path $env:TEMP 'MapleMono-NF-CN-extract'
    if (Test-Path $mapleTmp) { Remove-Item -Recurse -Force $mapleTmp }
    Invoke-WebRequest -Uri $mapleUrl -OutFile $mapleZip
    Expand-Archive -Force -Path $mapleZip -DestinationPath $mapleTmp
    Get-ChildItem $mapleTmp -Recurse -Include *.ttf,*.otf | ForEach-Object {
        $target = Join-Path $mapleDst $_.Name
        try {
            Copy-Item $_.FullName $target -Force -ErrorAction Stop
            $suffix = if ($_.Extension -ieq '.otf') { ' (OpenType)' } else { ' (TrueType)' }
            $valueName = [IO.Path]::GetFileNameWithoutExtension($_.Name) + $suffix
            New-ItemProperty -Path $mapleReg -Name $valueName -Value $target -PropertyType String -Force | Out-Null
        } catch {
            InitWin-WriteDetail "字体写入失败（可能正被某进程占用）：$($_.Name) - $_" -ForegroundColor Yellow
        }
    }
    Remove-Item -Recurse -Force $mapleZip,$mapleTmp -ErrorAction SilentlyContinue
}
