$powerSettings = @(
    [pscustomobject]@{ SubGroup = 'SUB_SLEEP'; Setting = 'STANDBYIDLE' }
    [pscustomobject]@{ SubGroup = 'SUB_VIDEO'; Setting = 'VIDEOIDLE' }
    [pscustomobject]@{ SubGroup = 'SUB_SLEEP'; Setting = 'HIBERNATEIDLE' }
)

InitWin-DefineEntry -Id System.Power.PowerAndExplorer -Name '电源 / 睡眠 / 屏幕' -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($setting in $powerSettings) {
        $result = InitWin-TestPowerSettingZero -SubGroup $setting.SubGroup -Setting $setting.Setting
        if ($result.Status -ne 'Desired') { $results.Add($result) }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', 'standby-timeout-ac', '0')
    InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', 'standby-timeout-dc', '0')
    InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', 'monitor-timeout-ac', '0')
    InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', 'monitor-timeout-dc', '0')
    InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', 'hibernate-timeout-ac', '0')
    InitWin-InvokeNative -FilePath powercfg -Arguments @('/change', 'hibernate-timeout-dc', '0')

    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
