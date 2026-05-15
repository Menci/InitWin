InitWin-DefineEntry -Id Packages.Extras.Hevc -Validate {
    if (Get-AppxPackage -Name 'Microsoft.HEVCVideoExtension*' -ErrorAction SilentlyContinue) {
        return InitWin-NewValidationResult -Status Desired
    }

    InitWin-NewValidationResult -Status Unset -Target 'AppxPackage: Microsoft.HEVCVideoExtension' -Current '<missing>' -Expected 'installed'
} -Apply {
    InitWin-WriteStep 'HEVC (free OEM SKU)'
    # Free OEM SKU 受设备资格限制；非 OEM 设备上 winget 通常会被 Store 后端拒绝。
    # 调研依据：https://github.com/microsoft/winget-cli/issues/908
    # 调研依据：https://github.com/ngkoi/hevc-extension
    InitWin-InvokeNative -FilePath winget -Arguments @(
        'install'
        '--id'
        '9N4WGH0Z6VHQ'
        '--source'
        'msstore'
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
        '--silent'
    ) -IgnoreExitCode
    if (-not (Get-AppxPackage -Name 'Microsoft.HEVCVideoExtension*' -ErrorAction SilentlyContinue)) {
        $hevcMessage = @(
            'HEVC (free) winget 安装失败 (干净 Win11 上几乎一定失败)。'
            '请手动操作：'
            '  1. 打开 https://store.rg-adguard.net/，输入'
            '       https://apps.microsoft.com/detail/9N4WGH0Z6VHQ'
            '     选 "Retail" 通道，下载文件名形如：'
            '       Microsoft.HEVCVideoExtension_*_x64__8wekyb3d8bbwe.appxbundle'
            '     (注意是 "Extension" 单数；"Extensions" 复数是付费版且 WMP 不工作)'
            '  2. 在管理员 PowerShell 里运行：'
            '       Add-AppxPackage -Path <下载到的 appxbundle 路径>'
        ) -join [Environment]::NewLine
        InitWin-WriteDetail $hevcMessage -ForegroundColor Yellow
    }
}
