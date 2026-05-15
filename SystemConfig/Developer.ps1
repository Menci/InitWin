$developerProperties = @(
    InitWin-NewRegistryProperty -Path 'HKCU:\Console\%%Startup' -Name 'DelegationConsole' -Type String -Value '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
    InitWin-NewRegistryProperty -Path 'HKCU:\Console\%%Startup' -Name 'DelegationTerminal' -Type String -Value '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
    InitWin-NewRegistryProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -Name 'Enabled' -Type DWord -Value 3
)

InitWin-DefineEntry -Id System.Developer.TerminalAndSudo -Validate {
    InitWin-TestRegistryPropertiesDesired -Properties $developerProperties
} -Apply {
    InitWin-WriteStep '终端 / sudo'
    InitWin-SetRegistryProperties -Properties $developerProperties
}
