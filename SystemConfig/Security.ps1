$uacPolicyProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Type DWord -Value 5
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'PromptOnSecureDesktop' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Type DWord -Value 1
)

$ucpdTaskPath = '\Microsoft\Windows\AppxDeploymentClient\'
$ucpdTaskName = 'UCPD velocity'
$powerShellExecutionPolicy = 'Bypass'

$windowsPowerShellExecutionPolicyProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' -Name 'ExecutionPolicy' -Type String -Value $powerShellExecutionPolicy
    InitWin-NewRegistryProperty -Path 'HKCU:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' -Name 'ExecutionPolicy' -Type String -Value $powerShellExecutionPolicy
)

InitWin-DefineEntry -Id System.Security.ExecutionPolicy -Validate {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($registryResult in @(InitWin-TestRegistryPropertiesDesired -Properties $windowsPowerShellExecutionPolicyProperties)) {
        if ($registryResult.Status -ne 'Desired') { $results.Add($registryResult) }
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-SetRegistryProperties -Properties $windowsPowerShellExecutionPolicyProperties

    try {
        Set-ExecutionPolicy -ExecutionPolicy $powerShellExecutionPolicy -Scope Process -Force -ErrorAction Stop
    } catch {
        InitWin-WriteDetail "Set-ExecutionPolicy 在 scope=Process 失败：$_" -ForegroundColor Yellow
    }
}

InitWin-DefineEntry -Id System.Security.UacPolicy -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $uacPolicyProperties
} -Apply {
    # UAC：等价于 "Notify me only when apps try to make changes to my computer (do not dim my desktop)"
    # 即四档滑块的第三档：仍弹提示，但不切换到 secure desktop。
    InitWin-SetRegistryProperties -Properties $uacPolicyProperties
}

InitWin-DefineEntry -Id System.Security.Ucpd -Validate {
    $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='UCPD'"
    if (-not $driver) {
        return InitWin-NewValidationResult -Status NotApplicable -Reason 'UCPD driver is not installed.'
    }

    $results = [System.Collections.Generic.List[object]]::new()
    if ($driver.StartMode -ne 'Disabled') {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target 'driver service: UCPD StartMode' -Current $driver.StartMode -Expected 'Disabled'))
    }

    $task = Get-ScheduledTask -TaskPath $ucpdTaskPath -TaskName $ucpdTaskName -ErrorAction SilentlyContinue
    if ($task -and ($task.State -ne 'Disabled')) {
        $results.Add((InitWin-NewValidationResult -Status Unset -Target "scheduled task: $ucpdTaskPath$ucpdTaskName" -Current $task.State -Expected 'Disabled'))
    }

    if ($results.Count -gt 0) { return $results }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    $task = Get-ScheduledTask -TaskPath $ucpdTaskPath -TaskName $ucpdTaskName -ErrorAction SilentlyContinue
    if ($task -and ($task.State -ne 'Disabled')) {
        Disable-ScheduledTask -InputObject $task | Out-Null
    }

    $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='UCPD'"
    if ($driver -and ($driver.StartMode -ne 'Disabled')) {
        InitWin-InvokeNative -FilePath sc.exe -Arguments @('config', 'UCPD', 'start=', 'disabled')
    }
}
