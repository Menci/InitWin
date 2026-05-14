# Init.ps1
# Windows 新机初始化脚本
# 每段命令前的注释对应用户口述的操作。
# 需要管理员权限运行（含 HKLM 写入、防火墙、远程桌面等操作）。

# PowerShell 执行策略：尽可能全部 Unrestricted（覆盖所有 scope）
foreach ($scope in 'LocalMachine','CurrentUser','Process') {
    try {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope $scope -Force -ErrorAction Stop
    } catch {
        Write-Warning "Set-ExecutionPolicy 在 scope=$scope 失败：$_"
    }
}

# 分节标题打印；脚本可重入，便于在重跑时看到进度
function Step($title) {
    Write-Host ''
    Write-Host "==> $title" -ForegroundColor Cyan
}

$Advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$Search   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'

Step '任务栏'

# 任务栏：隐藏 Search box
Set-ItemProperty -Path $Search -Name 'SearchboxTaskbarMode' -Type DWord -Value 0

# 任务栏：隐藏 Task view 按钮
Set-ItemProperty -Path $Advanced -Name 'ShowTaskViewButton' -Type DWord -Value 0

# 任务栏：隐藏 Widgets
Set-ItemProperty -Path $Advanced -Name 'TaskbarDa' -Type DWord -Value 0

# 任务栏：alignment 左侧（0 = 左，1 = 居中）
Set-ItemProperty -Path $Advanced -Name 'TaskbarAl' -Type DWord -Value 0

# 多显示器都显示任务栏（在单显示器上写入也无害，接上多显示器后自动生效）
Set-ItemProperty -Path $Advanced -Name 'MMTaskbarEnabled' -Type DWord -Value 1

# 多显示器：仅显示当前显示器上的任务（0 = 全部任务栏都显示所有，1 = 主+打开窗口的，2 = 仅打开窗口的那个显示器）
Set-ItemProperty -Path $Advanced -Name 'MMTaskbarMode' -Type DWord -Value 2

Step '颜色 / accent / 透明'
# 颜色：暗色模式（应用 + 系统都暗色）
$Personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
Set-ItemProperty -Path $Personalize -Name 'AppsUseLightTheme'    -Type DWord -Value 0
Set-ItemProperty -Path $Personalize -Name 'SystemUsesLightTheme' -Type DWord -Value 0

# 颜色：accent 配色 Orchid light
# Orchid Light 在 Windows 11 设置面板的颜色网格里对应基色 #C239B3 (R=C2, G=39, B=B3)。
# 同列下方的 "Orchid" 是其暗色变体 #9A0089。
# 来源：https://jmacthefatcat.github.io/win-10-colours/
#
# 编码注意（来源 https://github.com/Valer100/winaccent）：
#   - Explorer\Accent\AccentColor / StartColor / AccentColorMenu / StartColorMenu
#     和 DWM\AccentColor 都是 DWORD ABGR：0xAA BB GG RR
#   - DWM\ColorizationColor / ColorizationAfterglow 是 DWORD ARGB：0xAA RR GG BB
#   - AccentPalette 是 32 字节，8 个颜色 × 4 字节，字节序为 R,G,B,A（不是 BGRA）
#     第 4 个颜色（offset 12-15）是主 accent，第 8 个是 MotionAccent sentinel（alpha=0x00）
#
# 关于 AccentPalette（重要）：
# 真正的 8 阶渐变由 Windows.UI.dll 内部的私有 CColorTreatmentManager 生成
# (UISettings.GetColorValue / UIColorType.AccentLight3..AccentDark3)，算法未公开，
# 社区算法（winaccent 的 saturate+blend）经独立 dump 验证不准；GitHub 上也没有
# Orchid Light 的真实注册表 dump。所以这里在写完基色后，主动调用 WinRT 的 UISettings
# 让 Windows 自己算出当下的 8 个颜色，再写入 AccentPalette。
$Accent = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
$DWM    = 'HKCU:\Software\Microsoft\Windows\DWM'

# 下面的值 dump 自一台事先在 Settings → Personalization → Colors 选过 Orchid Light 的机器。
# 选用预定义 accent 时 Settings 不写 Accent\AccentColor 和 Accent\StartColor (HKCU 上不存在)，
# 只写 *Menu 系列和 DWM\AccentColor，所以这里也不写它们。

Set-ItemProperty -Path $Accent -Name 'AccentColorMenu' -Type DWord -Value 0xFFB339C2
# StartColorMenu 是同列下 "Orchid" 暗色变体 #A030AE
Set-ItemProperty -Path $Accent -Name 'StartColorMenu'  -Type DWord -Value 0xFFAE30A0

# DWM\AccentColor (ABGR)
Set-ItemProperty -Path $DWM -Name 'AccentColor'           -Type DWord -Value 0xFFB339C2
# DWM\ColorizationColor / Afterglow (ARGB)：alpha 0xC4
Set-ItemProperty -Path $DWM -Name 'ColorizationColor'     -Type DWord -Value 0xC4C239B3
Set-ItemProperty -Path $DWM -Name 'ColorizationAfterglow' -Type DWord -Value 0xC4C239B3
Set-ItemProperty -Path $DWM -Name 'ColorizationColorBalance' -Type DWord -Value 89
Set-ItemProperty -Path $DWM         -Name 'ColorPrevalence' -Type DWord -Value 0
Set-ItemProperty -Path $Personalize -Name 'ColorPrevalence' -Type DWord -Value 0

# AccentPalette: 8 槽 × RGBA，dump 自已选 Orchid Light 的机器。
# Microsoft 真实算法在 Windows.UI.dll 的 CColorTreatmentManager 私有函数里，未公开。
Set-ItemProperty -Path $Accent -Name 'AccentPalette' -Type Binary -Value ([byte[]](
    0xF4,0xB2,0xF1, 0x00,
    0xE1,0x83,0xD9, 0x00,
    0xCB,0x4F,0xBF, 0x00,
    0xC2,0x39,0xB3, 0x00,
    0xAE,0x30,0xA0, 0x00,
    0x7F,0x1D,0x75, 0x00,
    0x54,0x0A,0x4D, 0x00,
    0x2D,0x7D,0x9A, 0x00
))

# 颜色：打开 Transparency effects
Set-ItemProperty -Path $Personalize -Name 'EnableTransparency' -Type DWord -Value 1

Step '桌面图标'
# 桌面图标：隐藏「桌面图标设置」对话框里的所有系统图标
# 0 = 显示，1 = 隐藏。HideDesktopIcons\NewStartPanel 控制现代任务栏/资源管理器视图。
$HideIcons = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
if (-not (Test-Path $HideIcons)) { New-Item -Path $HideIcons -Force | Out-Null }
# Computer (This PC)
Set-ItemProperty -Path $HideIcons -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Type DWord -Value 1
# User's Files (用户的文件)
Set-ItemProperty -Path $HideIcons -Name '{59031A47-3F72-44A7-89C5-5595FE6B30EE}' -Type DWord -Value 1
# Network
Set-ItemProperty -Path $HideIcons -Name '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}' -Type DWord -Value 1
# Recycle Bin
Set-ItemProperty -Path $HideIcons -Name '{645FF040-5081-101B-9F08-00AA002F954E}' -Type DWord -Value 1
# Control Panel
Set-ItemProperty -Path $HideIcons -Name '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}' -Type DWord -Value 1

Step '锁屏'
# 锁屏：在登录界面显示锁屏壁纸（"Show the lock screen background picture on the sign-in screen"）
# 这个 toggle 由 HKLM 下的 GPO 值控制，需要管理员权限。0 = 显示，1 = 不显示。
# 默认就是显示，但显式写入以保险。
$SystemPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
if (-not (Test-Path $SystemPolicy)) { New-Item -Path $SystemPolicy -Force | Out-Null }
Set-ItemProperty -Path $SystemPolicy -Name 'DisableLogonBackgroundImage' -Type DWord -Value 0

# 锁屏：关闭 "Get fun facts, tips, tricks, and more on your lock screen"
# 这是 Windows Spotlight 在锁屏上的小贴士覆盖层。
$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
Set-ItemProperty -Path $CDM -Name 'RotatingLockScreenEnabled'        -Type DWord -Value 0
Set-ItemProperty -Path $CDM -Name 'RotatingLockScreenOverlayEnabled' -Type DWord -Value 0
# 同一开关 ("Get fun facts on lock screen") 在不同 Win11 版本下用过两个 ID
Set-ItemProperty -Path $CDM -Name 'SubscribedContent-338387Enabled'  -Type DWord -Value 0
Set-ItemProperty -Path $CDM -Name 'SubscribedContent-338380Enabled'  -Type DWord -Value 0

# 锁屏：关闭锁屏 Widgets（Windows 11 23H2+ 引入）和 "Suggest widgets for your lock screen"
# 正确的 key 在 PersonalizationCSP 下；之前用的 Dsh\AllowLockScreenWidgets 不存在。
# 禁用 widgets 本身后，"suggest widgets" 推荐也无从展示。
# 来源：https://woshub.com/lock-screen-widgets-windows/
$PersonalizationCSP = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
if (-not (Test-Path $PersonalizationCSP)) { New-Item -Path $PersonalizationCSP -Force | Out-Null }
Set-ItemProperty -Path $PersonalizationCSP -Name 'LockScreenWidgetsEnabled' -Type DWord -Value 0

Step '多任务 / Alt+Tab / Aero Shake'
# 多任务：Alt+Tab 不显示浏览器标签页（仅显示窗口）
# MultiTaskingAltTabFilter: 0=显示+所有Edge标签, 1=+最近5个, 2=+最近3个, 3=仅窗口
Set-ItemProperty -Path $Advanced -Name 'MultiTaskingAltTabFilter' -Type DWord -Value 3

# 多任务：开启 Title bar window shake（Aero Shake，抖动窗口最小化其他）
# DisallowShaking: 0 = 允许（开启抖动），1 = 禁止
Set-ItemProperty -Path $Advanced -Name 'DisallowShaking' -Type DWord -Value 0

Step '高级 / 任务栏 / 文件管理器 / 远程桌面 / 终端 / sudo'
# 高级 / 任务栏：开启 "End Task" 右键菜单项（Win11 22H2+ 开发者选项）
$TaskbarDevSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'
if (-not (Test-Path $TaskbarDevSettings)) { New-Item -Path $TaskbarDevSettings -Force | Out-Null }
Set-ItemProperty -Path $TaskbarDevSettings -Name 'TaskbarEndTask' -Type DWord -Value 1

# 高级 / 文件管理器：显示文件后缀名
Set-ItemProperty -Path $Advanced -Name 'HideFileExt' -Type DWord -Value 0
# 高级 / 文件管理器：显示隐藏文件
Set-ItemProperty -Path $Advanced -Name 'Hidden' -Type DWord -Value 1
# 高级 / 文件管理器：显示系统文件（受保护的操作系统文件）
Set-ItemProperty -Path $Advanced -Name 'ShowSuperHidden' -Type DWord -Value 1
# 高级 / 文件管理器：显示 empty drives
Set-ItemProperty -Path $Advanced -Name 'HideDrivesWithNoMedia' -Type DWord -Value 0
# 高级 / 文件管理器：开启 Win32 long path 支持（>260 字符）
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Type DWord -Value 1

# 高级 / 远程桌面：开启 Remote Desktop
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Type DWord -Value 0
# 同步开启防火墙规则
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

# 远程桌面：60 fps（DWM 帧间隔 15 ms ≈ 66.6 fps，是 60 fps 的标准推荐值）
# 写在 WinStations 根而非 RDP-Tcp 子节点（影响所有 stack 类型）
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' -Name 'DWMFRAMEINTERVAL' -Type DWord -Value 15

# 远程桌面：用户认证 (关闭 NLA，让低版本/异构客户端不受 CredSSP 限制)
# SecurityLayer: 0 = RDP Security Layer, 1 = Negotiate, 2 = SSL/TLS
# UserAuthentication: 0 = 不强制 NLA, 1 = 强制 NLA
# 注意：关掉 NLA 在公网上不安全；这里因用户明确要求而设置。
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer'      -Type DWord -Value 0
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Type DWord -Value 0

# 远程桌面：硬件加速（gpedit 两项的注册表等价写法）
# - "Prioritize H.264/AVC 444 graphics mode for Remote Desktop Connections" = Enabled
# - "Use hardware graphics adapters for all Remote Desktop Services sessions" = Enabled
$RdpPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
if (-not (Test-Path $RdpPolicy)) { New-Item -Path $RdpPolicy -Force | Out-Null }
Set-ItemProperty -Path $RdpPolicy -Name 'AVC444ModePreferred'  -Type DWord -Value 1
Set-ItemProperty -Path $RdpPolicy -Name 'bEnumerateHWBeforeSW' -Type DWord -Value 1

# 高级 / 终端：默认终端设为 Conhost（"Let Windows decide" 也走 conhost；这里硬选 conhost）
$StartupConsole = 'HKCU:\Console\%%Startup'
if (-not (Test-Path $StartupConsole)) { New-Item -Path $StartupConsole -Force | Out-Null }
# Conhost 的 CLSID
Set-ItemProperty -Path $StartupConsole -Name 'DelegationConsole'  -Type String -Value '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
Set-ItemProperty -Path $StartupConsole -Name 'DelegationTerminal' -Type String -Value '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'

# 高级 / 终端：开启 sudo（Win11 24H2+，Settings > System > For developers > Enable sudo）
# Enabled 的取值：0 = 禁用, 1 = 在新窗口运行（默认）, 2 = 输入禁用, 3 = 内联运行
$Sudo = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'
if (-not (Test-Path $Sudo)) { New-Item -Path $Sudo -Force | Out-Null }
Set-ItemProperty -Path $Sudo -Name 'Enabled' -Type DWord -Value 3

Step '网络 / 防火墙'
# 网络：把所有当前网络接口设为 Private
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

# 网络：未识别网络 (Unidentified networks) 的默认类别设为 Private
# 通过 Network List Manager Policies (gpedit.msc 下的同名节点) 注册表写入。
# Category: 0 = Public, 1 = Private, 2 = Domain Authenticated
$UnidentifiedNets = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\NetworkList\NetworkCategorization\UnidentifiedNetworks'
if (-not (Test-Path $UnidentifiedNets)) { New-Item -Path $UnidentifiedNets -Force | Out-Null }
Set-ItemProperty -Path $UnidentifiedNets -Name 'Category' -Type DWord -Value 1

# 网络：关闭"新网络弹窗"（"Do you want to allow your PC to be discoverable…"）
# 该 key 的存在即生效，不需要写值。
$NewNetworkWindow = 'HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff'
if (-not (Test-Path $NewNetworkWindow)) { New-Item -Path $NewNetworkWindow -Force | Out-Null }

# 注：Windows 不能把"以后接入的所有网络一律识别为 Private"完全自动化——
# (a) Set-NetConnectionProfile 处理当前已连的接口；
# (b) UnidentifiedNetworks Category=1 处理之后接入的"无法识别"网络；
# (c) NewNetworkWindowOff 关掉位置选择弹窗。
# 域加入网络始终被判定为 Domain，无法覆盖。
# (NetworkCategorization\IdentifiedNetworks 不存在，删去。)

# 防火墙：添加一条 "Allow ALL" 规则
# Custom / AllPrograms / Protocol Any / LocalIP Any / RemoteIP Any / Allow / Domain+Private+Public
# 同名规则若已存在则先删除，避免叠加。Inbound 方向。
# (省略 -Program / -LocalAddress / -RemoteAddress 即等价于 "Any"。)
Get-NetFirewallRule -DisplayName 'Allow ALL' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule `
    -DisplayName 'Allow ALL' `
    -Direction Inbound `
    -Action Allow `
    -Profile Domain,Private,Public `
    -Protocol Any `
    -Enabled True

Step '日期 / 时区 / 区域 / 语言'
# 日期时间：时区设为 China Standard Time (Asia/Shanghai, UTC+8)
Set-TimeZone -Id 'China Standard Time'

# 日期时间：关闭"自动设置时区"
# tzautoupdate 服务 Start = 4 表示 Disabled，3 表示 Manual（启用）
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name 'Start' -Type DWord -Value 4

# 日期时间：开启"自动设置时间"（NTP 同步）
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name 'Type' -Type String -Value 'NTP'
Set-Service -Name w32time -StartupType Automatic
Start-Service -Name w32time -ErrorAction SilentlyContinue
w32tm /resync /force | Out-Null

# 区域格式（HKCU\Control Panel\International）
$Intl = 'HKCU:\Control Panel\International'
# First day of week: 0=Monday ... 6=Sunday
Set-ItemProperty -Path $Intl -Name 'iFirstDayOfWeek' -Type String -Value '0'
# Short date: 2017-04-05
Set-ItemProperty -Path $Intl -Name 'sShortDate' -Type String -Value 'yyyy-MM-dd'
# Long date: Wednesday, April 5, 2017
Set-ItemProperty -Path $Intl -Name 'sLongDate'  -Type String -Value 'dddd, MMMM d, yyyy'
# Short time: 09:40 / 14:40 (24h, no leading zero on hour 不在标准格式内 —
# Windows 区域设置 short time 标准就是 HH:mm；"9:40" 这种带可变长度的实际显示由
# H:mm 控制。用户给的样例既有 09 又有 14，使用 HH:mm 更稳定)
Set-ItemProperty -Path $Intl -Name 'sShortTime'  -Type String -Value 'HH:mm'
# Long time: 09:40:07 / 14:40:07
Set-ItemProperty -Path $Intl -Name 'sTimeFormat' -Type String -Value 'HH:mm:ss'
# Measurement system: 0 = Metric, 1 = US
Set-ItemProperty -Path $Intl -Name 'iMeasure' -Type String -Value '0'

Step 'Visual effects'
# Visual effects：开启 Transparency effects (Mica)
# 已在前面"颜色"小节设置过 EnableTransparency=1（Settings 里两个 toggle 共用同一注册表），
# 此处不重复写入，仅记录两者等价。

# Visual effects：关闭 Animation effects
# 这个 toggle 实际通过 SystemParametersInfo 多个 SPI 综合控制，对应几处注册表 + 一次广播。
# 1) UserPreferencesMask：关闭菜单/工具提示/选择渐隐等动画
# 字节含义参见 https://learn.microsoft.com/zh-cn/windows/win32/api/winuser/nf-winuser-systemparametersinfoa
# 注：这一组 8 字节不是从 24H2 实测 dump 得到，而是社区"关闭动画"模板值；如果你
# 在意精确性，应在 24H2 上手动关掉 Animation effects 后 reg query 替换。
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Type Binary -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00))
# 2) 最小化/最大化动画
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Type String -Value '0'
# 3) 任务栏动画 / 列表视图渐隐选择 / 透明 listbox 选择 / 工具栏动画
Set-ItemProperty -Path $Advanced -Name 'TaskbarAnimations'      -Type DWord -Value 0
Set-ItemProperty -Path $Advanced -Name 'ListviewAlphaSelect'    -Type DWord -Value 0
Set-ItemProperty -Path $Advanced -Name 'ListviewShadow'         -Type DWord -Value 0
# 4) Visual FX 总开关切到 "Custom"，让上面的细项生效（1 = Best appearance, 2 = Best performance, 3 = Custom）
$VFX = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
if (-not (Test-Path $VFX)) { New-Item -Path $VFX -Force | Out-Null }
Set-ItemProperty -Path $VFX -Name 'VisualFXSetting' -Type DWord -Value 3
# 5) SPI_SETCLIENTAREAANIMATION = 0 并广播 WM_SETTINGCHANGE，让正在运行的程序立刻感知
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SPI {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, UIntPtr pvParam, uint fWinIni);
}
'@ -ErrorAction SilentlyContinue
# SPI_SETCLIENTAREAANIMATION = 0x1043; SPIF_UPDATEINIFILE|SPIF_SENDCHANGE = 0x03
[void][SPI]::SystemParametersInfo(0x1043, 0, [UIntPtr]::Zero, 0x03)

Step 'Non-Unicode locale / UTF-8 / 复制到欢迎屏 & 新用户'
# Locale for non-Unicode programs：Chinese (Simplified, China)
Set-WinSystemLocale -SystemLocale 'zh-CN'

# 开启实验性 UTF-8（Beta: Use Unicode UTF-8 for worldwide language support）
# 直接把三套代码页强制为 65001。
$NlsCodePage = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
Set-ItemProperty -Path $NlsCodePage -Name 'ACP'    -Type String -Value '65001'
Set-ItemProperty -Path $NlsCodePage -Name 'OEMCP'  -Type String -Value '65001'
Set-ItemProperty -Path $NlsCodePage -Name 'MACCP'  -Type String -Value '65001'

# Copy current user settings to:
#   - Welcome screen and system account
#   - New user accounts
# 用 Windows 11 自带的 Copy-UserInternationalSettingsToSystem cmdlet（International 模块）。
# 它复制：Display language / Input language / Regional Format(locale) / Location(GeoID)，
# 等价于 intl.cpl ,2 对话框里的两个 checkbox。需要管理员，且重启后才完全生效。
# 来源：https://learn.microsoft.com/en-us/powershell/module/international/copy-userinternationalsettingstosystem
try {
    Import-Module International -ErrorAction Stop
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
} catch {
    Write-Warning "Copy-UserInternationalSettingsToSystem 不可用（需要 Windows 11+），跳过：$_"
}

Step 'Optional features (FoD) / Windows features'
# Optional features (Features on Demand, FoD)：
#   - Chinese (Simplified) Supplemental Fonts (含 Noto Sans/Serif CJK SC、DengXian 等)
#   - OpenSSH Client
# Get-WindowsCapability -Name 不支持通配符，必须用准确名字。
# 来源：https://learn.microsoft.com/en-us/powershell/module/dism/get-windowscapability
foreach ($cap in 'Language.Fonts.Hans~~~und-HANS~0.0.1.0', 'OpenSSH.Client~~~~0.0.1.0') {
    $state = Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue
    if ($null -eq $state) {
        Write-Warning "Capability 不存在于本机：$cap"
        continue
    }
    if ($state.State -ne 'Installed') {
        Write-Host "Installing optional feature: $cap"
        Add-WindowsCapability -Online -Name $cap | Out-Null
    }
}

# Turn Windows features on or off：
#   - Hyper-V (含管理工具与平台)
#   - WSL (Windows Subsystem for Linux + VirtualMachinePlatform，wsl2 必需)
#   - Telnet Client
#   - TFTP Client
#   - Windows Sandbox
# 用 Enable-WindowsOptionalFeature -All -NoRestart；安装完后系统需要重启。
$features = @(
    'Microsoft-Hyper-V-All',
    'Microsoft-Windows-Subsystem-Linux',
    'VirtualMachinePlatform',
    'TelnetClient',
    'TFTP',
    'Containers-DisposableClientVM'
)
foreach ($f in $features) {
    $state = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
    if ($null -eq $state) {
        Write-Warning "Windows feature 不存在于本机：$f"
        continue
    }
    if ($state.State -ne 'Enabled') {
        Write-Host "Enabling Windows feature: $f"
        Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null
    }
}

# ============================================================
# 以上为快速修改阶段（注册表 / Windows 设置等，秒级完成）。
# 新加的"快速"项目，除非特别说明，都应该插入到这一行之上。
# ============================================================

Step 'UAC'
# UAC：等价于 "Notify me only when apps try to make changes to my computer (do not dim my desktop)"
# 即四档滑块的第三档：仍弹提示，但不切换到 secure desktop。
$UacPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
# 5 = Prompt for consent for non-Windows binaries
Set-ItemProperty -Path $UacPolicy -Name 'ConsentPromptBehaviorAdmin' -Type DWord -Value 5
# 0 = 不切换到安全桌面
Set-ItemProperty -Path $UacPolicy -Name 'PromptOnSecureDesktop' -Type DWord -Value 0
# UAC 总开关保持开启
Set-ItemProperty -Path $UacPolicy -Name 'EnableLUA' -Type DWord -Value 1

Step '电源 / 睡眠 / 屏幕'
# 电源：禁用自动睡眠和自动关屏（AC 与 DC 都设为 0 = 永不）
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
# 顺手把休眠超时也关掉，避免长时间挂着自动 hibernate
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0

# 让 explorer.exe 重启以应用任务栏相关的更改；放在这里以避免后续安装过程被打断
Stop-Process -Name explorer -Force

# ============================================================
# 软件安装阶段（Store / winget / installer 等，会跑较久）。
# 新加的"安装类"项目，除非特别说明，都应该插入到这一行之下。
# 在此之前会要求用户登录 Microsoft Store；之后的步骤可无人值守。
# ============================================================

# Microsoft Store 安装：先要求用户登录 Store
Write-Host ''
Write-Host '======================================================================' -ForegroundColor Yellow
Write-Host '快速修改部分已完成。下面是软件安装阶段，会跑较久。'                -ForegroundColor Yellow
Write-Host '请在 Microsoft Store 中登录你的 Microsoft 账号，登录后按任意键继续...' -ForegroundColor Yellow
Write-Host '======================================================================' -ForegroundColor Yellow
Start-Process 'ms-windows-store:'
[void][Console]::ReadKey($true)

Step 'Microsoft Store 应用安装'
# Microsoft Store 应用清单（用 winget 从 msstore 源安装）
# 名称 -> Store ID
$storeApps = [ordered]@{
    'Windows App (msrdc)'  = '9N1F85V9T8BN'
    'Debian (WSL)'         = '9MSVKQC78PK6'
    'WSL (Microsoft Store)' = '9P9TQF7MRM4R'
    'GIMP'                 = '9PNSJCLXDZ0V'
    'Inkscape'             = '9PD9BHGLFC7H'
    'Telegram Desktop'     = '9NZTWSQNTD0S'
    'NanaZip'              = '9N8G7TSCL18R'
    'Snipaste'             = '9P1WXPKB68KX'
    'PowerToys'            = 'XP89DCGQ3K6VLD'
    'PowerShell'           = '9MZ1SNWT0N5D'
    # Python：Microsoft Store 上的 Python 由 PSF 官方维护，安装后随 Store 自动跟最新。
    # 这里写主版本（3.13），Store 会装该主版本下的最新次版本；新主版本出来时刷新这里。
    'Python (latest)'      = '9PNRBTZXMB4Z'  # Python 3.13
    'Twinkle Tray'         = '9PLJWWSV01LK'
}
foreach ($name in $storeApps.Keys) {
    $id = $storeApps[$name]
    Write-Host "Installing from Microsoft Store: $name ($id)"
    winget install --id $id --source msstore --accept-package-agreements --accept-source-agreements --silent
}

Step 'HEVC (free OEM SKU)'
# HEVC Video Extensions from Device Manufacturer (free OEM SKU, ID 9N4WGH0Z6VHQ)
# 这个包受 Microsoft 设备资格 (device-manufacturer eligibility) 限制，winget --source msstore
# 在非 OEM 设备上几乎一定被 Store 后端拒绝。这里仍尝试一次：
#   - 在带 OEM HEVC 授权的预装机上，winget 可装；
#   - 在干净安装 Windows 11 上，绝大概率失败，需要手动下载 .appxbundle 然后 Add-AppxPackage。
# 调研依据：
#   - https://github.com/microsoft/winget-cli/issues/908 (winget 不携带 MSA license context)
#   - https://github.com/ngkoi/hevc-extension (社区镜像 + 一行 Add-AppxPackage 的范式)
#   - https://www.windowslatest.com/2025/07/16/can-you-get-hevc-codec-for-free-on-windows-11/
$hevcInstalled = Get-AppxPackage -Name 'Microsoft.HEVCVideoExtension*' -ErrorAction SilentlyContinue
if ($hevcInstalled) {
    Write-Host "HEVC 已安装：$($hevcInstalled.Name) $($hevcInstalled.Version)，跳过。"
} else {
    Write-Host 'Trying HEVC (free OEM SKU) via winget…'
    winget install --id 9N4WGH0Z6VHQ --source msstore --accept-package-agreements --accept-source-agreements --silent
    # winget 退出码非 0 不一定代表"失败"（已安装也是非 0）。这里以 Get-AppxPackage 为准复查。
    if (-not (Get-AppxPackage -Name 'Microsoft.HEVCVideoExtension*' -ErrorAction SilentlyContinue)) {
        Write-Warning @'
HEVC (free) winget 安装失败 (干净 Win11 上几乎一定失败)。
请手动操作：
  1. 打开 https://store.rg-adguard.net/，输入
       https://apps.microsoft.com/detail/9N4WGH0Z6VHQ
     选 "Retail" 通道，下载文件名形如：
       Microsoft.HEVCVideoExtension_*_x64__8wekyb3d8bbwe.appxbundle
     (注意是 "Extension" 单数；"Extensions" 复数是付费版且 WMP 不工作)
  2. 在管理员 PowerShell 里运行：
       Add-AppxPackage -Path <下载到的 appxbundle 路径>
'@
    }
}

Step 'winget 公共源安装'
# winget 公共源安装（不需要 Store 登录，可无人值守）
$wingetApps = [ordered]@{
    'mitmproxy'          = 'mitmproxy.mitmproxy'   # Store 无上架
    'Visual Studio Code' = 'Microsoft.VisualStudioCode'
    'Git for Windows'    = 'Git.Git'
    'Bitwarden'          = 'Bitwarden.Bitwarden'   # 桌面版安装包，不是 Store 版
    # Office 365 Apps：winget 包 Microsoft.Office 实际上调用 Office Deployment Tool
    # （ClickToRun 的部署器），等价于官网 ClickToRun 部署，但 winget 一行搞定。
    'Office 365 Apps'    = 'Microsoft.Office'
    '.NET SDK'           = 'Microsoft.DotNet.SDK.10'
    'VLC'                = 'VideoLAN.VLC'
    'Wireshark'          = 'WiresharkFoundation.Wireshark'
    'Azure CLI'          = 'Microsoft.AzureCLI'
    'kubectl'            = 'Kubernetes.kubectl'
}
foreach ($name in $wingetApps.Keys) {
    $id = $wingetApps[$name]
    Write-Host "Installing via winget: $name ($id)"
    winget install --id $id --source winget --accept-package-agreements --accept-source-agreements --silent
}

Step 'Maple Mono NF CN 字体'
# Maple Mono NF CN：Maple Mono 的 Nerd Fonts + 中文 (CJK) 变体。
# 没有 winget/Chocolatey 官方包；直接从 GitHub Release 下载 zip 安装到当前用户。
# 来源：https://github.com/subframe7536/maple-font
$mapleZip = Join-Path $env:TEMP 'MapleMono-NF-CN.zip'
$mapleDst = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$mapleReg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$mapleUrl = 'https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-CN.zip'
# 幂等性：检查注册表里是否已有以 MapleMono-NF-CN 开头的项；有就跳过。
$mapleAlreadyInstalled = Get-ItemProperty -Path $mapleReg -ErrorAction SilentlyContinue |
    ForEach-Object { $_.PSObject.Properties.Name } |
    Where-Object { $_ -like 'MapleMono-NF-CN*' }
if ($mapleAlreadyInstalled) {
    Write-Host "Maple Mono NF CN 已安装，跳过。"
} else {
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
            Write-Warning "字体写入失败（可能正被某进程占用）：$($_.Name) — $_"
        }
    }
    Remove-Item -Recurse -Force $mapleZip,$mapleTmp -ErrorAction SilentlyContinue
}
