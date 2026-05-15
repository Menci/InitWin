$powerTimeoutSettings = @(
    # powercfg /change takes minutes, while powercfg /query reports setting indexes in seconds.
    [pscustomobject]@{ SubGroup = 'SUB_SLEEP'; Setting = 'STANDBYIDLE'; AcChange = 'standby-timeout-ac'; DcChange = 'standby-timeout-dc'; AcMinutes = 0; DcMinutes = 0 }
    [pscustomobject]@{ SubGroup = 'SUB_VIDEO'; Setting = 'VIDEOIDLE'; AcChange = 'monitor-timeout-ac'; DcChange = 'monitor-timeout-dc'; AcMinutes = 0; DcMinutes = 3 }
    [pscustomobject]@{ SubGroup = 'SUB_SLEEP'; Setting = 'HIBERNATEIDLE'; AcChange = 'hibernate-timeout-ac'; DcChange = 'hibernate-timeout-dc'; AcMinutes = 0; DcMinutes = 0 }
)

InitWin-DefineEntry -Id System.Power.PowerAndExplorer -Name '电源 / 睡眠 / 屏幕' -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($setting in $powerTimeoutSettings) {
        $result = InitWin-TestPowerSettingValue `
            -SubGroup $setting.SubGroup `
            -Setting $setting.Setting `
            -ExpectedAc (InitWin-ConvertPowerTimeoutMinutesToSeconds -Minutes $setting.AcMinutes) `
            -ExpectedDc (InitWin-ConvertPowerTimeoutMinutesToSeconds -Minutes $setting.DcMinutes)
        if ($result.Status -ne 'Desired') { $results.Add($result) }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    foreach ($setting in $powerTimeoutSettings) {
        InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', $setting.AcChange, ([string] $setting.AcMinutes))
        InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', $setting.DcChange, ([string] $setting.DcMinutes))
    }

    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
