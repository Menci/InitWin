$uacPolicyProperties = @(
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Type DWord -Value 5
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'PromptOnSecureDesktop' -Type DWord -Value 0
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Type DWord -Value 1
)

$ucpdTaskPath = '\Microsoft\Windows\AppxDeploymentClient\'
$ucpdTaskName = 'UCPD velocity'

InitWin-DefineEntry -Id System.Security.ExecutionPolicy -Validate {
    foreach ($scope in 'LocalMachine','CurrentUser') {
        if ((Get-ExecutionPolicy -Scope $scope) -ne 'Unrestricted') {
            return InitWin-NewValidationResult -Status Unset -Target "ExecutionPolicy: $scope" -Current (Get-ExecutionPolicy -Scope $scope) -Expected 'Unrestricted'
        }
    }
    InitWin-NewValidationResult -Status Desired
} -Apply {
    # PowerShell 执行策略：尽可能全部 Unrestricted（覆盖所有 scope）
    foreach ($scope in 'LocalMachine','CurrentUser','Process') {
        try {
            Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope $scope -Force -ErrorAction Stop
        } catch {
            InitWin-WriteDetail "Set-ExecutionPolicy 在 scope=$scope 失败：$_" -ForegroundColor Yellow
        }
    }
}

InitWin-DefineEntry -Id System.Security.UacPolicy -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $uacPolicyProperties
} -Apply {
    InitWin-WriteStep 'UAC'
    # UAC：等价于 "Notify me only when apps try to make changes to my computer (do not dim my desktop)"
    # 即四档滑块的第三档：仍弹提示，但不切换到 secure desktop。
    InitWin-SetRegistryProperties -Properties $uacPolicyProperties
}

InitWin-DefineEntry -Id System.Security.Ucpd -Validate {
    $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='UCPD'"
    if (-not $driver) {
        return InitWin-NewValidationResult -Status NotApplicable -Reason 'UCPD driver is not installed.'
    }

    if ($driver.StartMode -ne 'Disabled') {
        return InitWin-NewValidationResult -Status Unset -Target 'driver service: UCPD StartMode' -Current $driver.StartMode -Expected 'Disabled'
    }

    $task = Get-ScheduledTask -TaskPath $ucpdTaskPath -TaskName $ucpdTaskName -ErrorAction SilentlyContinue
    if ($task -and ($task.State -ne 'Disabled')) {
        return InitWin-NewValidationResult -Status Unset -Target "scheduled task: $ucpdTaskPath$ucpdTaskName" -Current $task.State -Expected 'Disabled'
    }

    InitWin-NewValidationResult -Status Desired
} -Apply {
    InitWin-WriteStep 'UCPD'

    $task = Get-ScheduledTask -TaskPath $ucpdTaskPath -TaskName $ucpdTaskName -ErrorAction SilentlyContinue
    if ($task -and ($task.State -ne 'Disabled')) {
        Disable-ScheduledTask -InputObject $task | Out-Null
    }

    $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='UCPD'"
    if ($driver -and ($driver.StartMode -ne 'Disabled')) {
        InitWin-InvokeNative -FilePath sc.exe -Arguments @('config', 'UCPD', 'start=', 'disabled')
    }
}
