function InitWin-QuoteNativeArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Argument)

    if (($Argument.Length -gt 0) -and ($Argument -notmatch '[\s"]')) { return $Argument }

    $result = [System.Text.StringBuilder]::new()
    [void] $result.Append('"')

    $backslashes = 0
    foreach ($char in $Argument.ToCharArray()) {
        if ($char -eq '\') {
            $backslashes++
            continue
        }

        if ($char -eq '"') {
            [void] $result.Append('\' * (($backslashes * 2) + 1))
            [void] $result.Append('"')
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            [void] $result.Append('\' * $backslashes)
            $backslashes = 0
        }
        [void] $result.Append($char)
    }

    if ($backslashes -gt 0) {
        [void] $result.Append('\' * ($backslashes * 2))
    }
    [void] $result.Append('"')
    [string] $result
}

function InitWin-JoinNativeArguments {
    param([string[]] $Arguments = @())

    (@($Arguments) | ForEach-Object { InitWin-QuoteNativeArgument ([string] $_) }) -join ' '
}

function InitWin-EnsurePseudoConsoleType {
    if ('InitWin.PseudoConsoleProcess' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace InitWin {
    public sealed class PseudoConsoleProcess : IDisposable {
        private const int EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
        private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const int WAIT_OBJECT_0 = 0;
        private const int WAIT_TIMEOUT = 0x00000102;
        private const int INFINITE = unchecked((int)0xFFFFFFFF);
        private static readonly IntPtr PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = (IntPtr)0x00020016;

        private IntPtr pseudoConsole;
        private IntPtr processHandle;
        private IntPtr threadHandle;
        private IntPtr attributeList;
        private IntPtr inputWrite;

        public Stream OutputStream { get; private set; }
        public int ProcessId { get; private set; }

        public PseudoConsoleProcess(string commandLine, string workingDirectory, short columns, short rows) {
            IntPtr inputRead = IntPtr.Zero;
            IntPtr outputRead = IntPtr.Zero;
            IntPtr outputWrite = IntPtr.Zero;
            IntPtr localInputWrite = IntPtr.Zero;
            bool started = false;

            try {
                SECURITY_ATTRIBUTES securityAttributes = new SECURITY_ATTRIBUTES();
                securityAttributes.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                securityAttributes.lpSecurityDescriptor = IntPtr.Zero;
                securityAttributes.bInheritHandle = false;

                if (!CreatePipe(out inputRead, out localInputWrite, ref securityAttributes, 0)) {
                    ThrowLastWin32Error("CreatePipe(input)");
                }
                if (!CreatePipe(out outputRead, out outputWrite, ref securityAttributes, 0)) {
                    ThrowLastWin32Error("CreatePipe(output)");
                }

                int hr = CreatePseudoConsole(new COORD(columns, rows), inputRead, outputWrite, 0, out pseudoConsole);
                if (hr != 0) {
                    Marshal.ThrowExceptionForHR(hr);
                }

                CloseIfNeeded(ref inputRead);
                CloseIfNeeded(ref outputWrite);
                inputWrite = localInputWrite;
                localInputWrite = IntPtr.Zero;
                OutputStream = new FileStream(new SafeFileHandle(outputRead, true), FileAccess.Read, 4096, false);
                outputRead = IntPtr.Zero;

                IntPtr attributeListSize = IntPtr.Zero;
                InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeListSize);
                attributeList = Marshal.AllocHGlobal(attributeListSize);
                if (!InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeListSize)) {
                    ThrowLastWin32Error("InitializeProcThreadAttributeList");
                }
                if (!UpdateProcThreadAttribute(attributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, pseudoConsole, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) {
                    ThrowLastWin32Error("UpdateProcThreadAttribute");
                }

                STARTUPINFOEX startupInfo = new STARTUPINFOEX();
                startupInfo.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
                startupInfo.lpAttributeList = attributeList;

                PROCESS_INFORMATION processInformation;
                string mutableCommandLine = commandLine;
                bool created = CreateProcessW(
                    null,
                    mutableCommandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                    IntPtr.Zero,
                    workingDirectory,
                    ref startupInfo,
                    out processInformation);
                if (!created) {
                    ThrowLastWin32Error("CreateProcessW");
                }

                processHandle = processInformation.hProcess;
                threadHandle = processInformation.hThread;
                ProcessId = processInformation.dwProcessId;
                started = true;
            } finally {
                CloseIfNeeded(ref inputRead);
                CloseIfNeeded(ref outputWrite);
                CloseIfNeeded(ref localInputWrite);
                if (outputRead != IntPtr.Zero) { CloseIfNeeded(ref outputRead); }
                if (!started) { Dispose(); }
            }
        }

        public bool HasExited {
            get {
                if (processHandle == IntPtr.Zero) { return true; }
                int result = WaitForSingleObject(processHandle, 0);
                if (result == WAIT_OBJECT_0) { return true; }
                if (result == WAIT_TIMEOUT) { return false; }
                ThrowLastWin32Error("WaitForSingleObject");
                return false;
            }
        }

        public int WaitForExit() {
            if (processHandle == IntPtr.Zero) { return 0; }
            int result = WaitForSingleObject(processHandle, INFINITE);
            if (result != WAIT_OBJECT_0) { ThrowLastWin32Error("WaitForSingleObject"); }
            int exitCode;
            if (!GetExitCodeProcess(processHandle, out exitCode)) { ThrowLastWin32Error("GetExitCodeProcess"); }
            return exitCode;
        }

        public void CloseConsole() {
            if (pseudoConsole != IntPtr.Zero) {
                ClosePseudoConsole(pseudoConsole);
                pseudoConsole = IntPtr.Zero;
            }
        }

        public void Dispose() {
            CloseConsole();
            if (OutputStream != null) {
                OutputStream.Dispose();
                OutputStream = null;
            }
            CloseIfNeeded(ref inputWrite);
            if (attributeList != IntPtr.Zero) {
                DeleteProcThreadAttributeList(attributeList);
                Marshal.FreeHGlobal(attributeList);
                attributeList = IntPtr.Zero;
            }
            CloseIfNeeded(ref threadHandle);
            CloseIfNeeded(ref processHandle);
        }

        private static void CloseIfNeeded(ref IntPtr handle) {
            if (handle != IntPtr.Zero && handle != new IntPtr(-1)) {
                CloseHandle(handle);
                handle = IntPtr.Zero;
            }
        }

        private static void ThrowLastWin32Error(string operation) {
            throw new Win32Exception(Marshal.GetLastWin32Error(), operation);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct COORD {
            public short X;
            public short Y;
            public COORD(short x, short y) { X = x; Y = y; }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)] public bool bInheritHandle;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFOEX {
            public STARTUPINFO StartupInfo;
            public IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, ref SECURITY_ATTRIBUTES lpPipeAttributes, int nSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool UpdateProcThreadAttribute(IntPtr lpAttributeList, int dwFlags, IntPtr Attribute, IntPtr lpValue, IntPtr cbSize, IntPtr lpPreviousValue, IntPtr lpReturnSize);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CreateProcessW(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, int dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFOEX lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, int dwFlags, out IntPtr phPC);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern void ClosePseudoConsole(IntPtr hPC);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern int WaitForSingleObject(IntPtr hHandle, int dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetExitCodeProcess(IntPtr hProcess, out int lpExitCode);
    }
}
'@
}

function InitWin-EnsureConsoleModeType {
    if ('InitWin.ConsoleMode' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace InitWin {
    public static class ConsoleMode {
        private const int STD_OUTPUT_HANDLE = -11;
        private const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

        public static bool EnableVirtualTerminalOutput() {
            IntPtr outputHandle = GetStdHandle(STD_OUTPUT_HANDLE);
            if (outputHandle == IntPtr.Zero || outputHandle == new IntPtr(-1)) { return false; }

            uint mode;
            if (!GetConsoleMode(outputHandle, out mode)) { return false; }
            if ((mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING) == ENABLE_VIRTUAL_TERMINAL_PROCESSING) { return true; }
            return SetConsoleMode(outputHandle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    }
}
'@
}

function InitWin-EnableVirtualTerminalOutput {
    if ([Console]::IsOutputRedirected) { return $false }

    try {
        InitWin-EnsureConsoleModeType
        [InitWin.ConsoleMode]::EnableVirtualTerminalOutput()
    } catch {
        $false
    }
}

function InitWin-TestPseudoConsoleAvailable {
    if ([Console]::IsOutputRedirected) { return $false }
    try {
        InitWin-EnsurePseudoConsoleType
        $true
    } catch {
        $false
    }
}

function InitWin-GetNativeOutputDefaultContentWidth {
    if ([Console]::IsOutputRedirected) { return [int]::MaxValue }
    try {
        [Math]::Max(20, [Console]::BufferWidth - '│  │    │ '.Length - 1)
    } catch {
        [int]::MaxValue
    }
}

function InitWin-NewNativeOutputRenderer {
    [pscustomobject]@{
        Prefix = '│  │    │ '
        Columns = (InitWin-GetNativeOutputDefaultContentWidth)
        UseVirtualTerminal = (InitWin-EnableVirtualTerminalOutput)
        Line = [System.Collections.Generic.List[char]]::new()
        CursorRow = 0
        CursorColumn = 0
        SavedCursorRow = 0
        SavedCursorColumn = 0
        HasRenderedLine = $false
        HasRenderedDynamicLine = $false
        LastRenderedLineText = $null
        LineIsDynamic = $false
        LineHasCarriageReturn = $false
        PendingCarriageReturn = $false
        Dirty = $false
        PendingText = ''
    }
}

function InitWin-ResolveNativeOutputPendingCarriageReturn {
    param([Parameter(Mandatory)][object] $Renderer)

    if (-not $Renderer.PendingCarriageReturn) { return }
    $Renderer.LineIsDynamic = $true
    $Renderer.LineHasCarriageReturn = $true
    InitWin-RenderNativeOutputLine -Renderer $Renderer
    $Renderer.CursorColumn = 0
    $Renderer.PendingCarriageReturn = $false
}

function InitWin-TestNativeOutputCsiCanPrecedeLineFeed {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $ParameterText,
        [Parameter(Mandatory)][char] $Final
    )

    if ($Final -ceq 'm') { return $true }
    if ((($Final -ceq 'h') -or ($Final -ceq 'l')) -and $ParameterText.StartsWith('?')) { return $true }
    $false
}

function InitWin-GetNativeOutputLineText {
    param([Parameter(Mandatory)][object] $Renderer)

    (-join $Renderer.Line).TrimEnd()
}

function InitWin-GetNativeOutputLineHeight {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [switch] $ExplicitBlank
    )

    if ($ExplicitBlank -and ($Text.Length -eq 0)) { return 1 }
    if ($Text.Length -eq 0) { return 1 }
    if (($Renderer.Columns -eq [int]::MaxValue) -or ($Renderer.Columns -le 0)) { return 1 }
    [int] ([Math]::Floor(($Text.Length - 1) / $Renderer.Columns) + 1)
}

function InitWin-SetNativeOutputLineText {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text
    )

    $Renderer.Line.Clear()
    foreach ($char in $Text.ToCharArray()) {
        $Renderer.Line.Add($char)
    }
    $Renderer.CursorColumn = [Math]::Min($Renderer.CursorColumn, $Renderer.Line.Count)
    $Renderer.Dirty = $true
}

function InitWin-RenderNativeOutputLine {
    param([Parameter(Mandatory)][object] $Renderer)

    if (-not $Renderer.UseVirtualTerminal) { return }
    if (-not $Renderer.Dirty) { return }

    $lineText = InitWin-GetNativeOutputLineText -Renderer $Renderer
    $escape = [char] 27
    if ($lineText.Length -eq 0) {
        if ($Renderer.HasRenderedDynamicLine) {
            [Console]::Write("`r${escape}[2K")
        }
        $Renderer.HasRenderedDynamicLine = $false
        $Renderer.LastRenderedLineText = $null
        $Renderer.Dirty = $false
        return
    }

    if (-not $Renderer.LineIsDynamic) { return }

    if (($Renderer.Columns -ne [int]::MaxValue) -and ($lineText.Length -gt $Renderer.Columns)) {
        $lineText = $lineText.Substring(0, $Renderer.Columns)
    }

    $cursorColumn = [Math]::Min($Renderer.CursorColumn, $lineText.Length)
    if (($Renderer.HasRenderedDynamicLine) -and ($Renderer.LastRenderedLineText -ceq $lineText)) {
        $Renderer.Dirty = $false
        return
    }

    [Console]::Write("`r$($Renderer.Prefix)$lineText${escape}[K")
    $hostColumn = $Renderer.Prefix.Length + $cursorColumn
    [Console]::Write("`r")
    if ($hostColumn -gt 0) { [Console]::Write("${escape}[${hostColumn}C") }
    $Renderer.HasRenderedLine = $true
    $Renderer.HasRenderedDynamicLine = $true
    $Renderer.LastRenderedLineText = $lineText
    $Renderer.Dirty = $false
}

function InitWin-CommitNativeOutputLine {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [switch] $ExplicitBlank
    )

    $lineText = InitWin-GetNativeOutputLineText -Renderer $Renderer
    if ($Renderer.UseVirtualTerminal) {
        $escape = [char] 27
        if (($lineText.Length -gt 0) -or $ExplicitBlank) {
            [Console]::Write("`r$($Renderer.Prefix)$lineText${escape}[K")
            [Console]::WriteLine()
        } elseif ($Renderer.HasRenderedDynamicLine) {
            [Console]::Write("`r${escape}[2K")
        }
    } else {
        if (($lineText.Length -gt 0) -or $ExplicitBlank) {
            InitWin-WriteCommandOutput $lineText
        }
    }
    $lineHeight = InitWin-GetNativeOutputLineHeight -Renderer $Renderer -Text $lineText -ExplicitBlank:$ExplicitBlank
    $Renderer.Line.Clear()
    $Renderer.CursorRow += $lineHeight
    $Renderer.CursorColumn = 0
    $Renderer.HasRenderedLine = $false
    $Renderer.HasRenderedDynamicLine = $false
    $Renderer.LastRenderedLineText = $null
    $Renderer.LineIsDynamic = $false
    $Renderer.LineHasCarriageReturn = $false
    $Renderer.PendingCarriageReturn = $false
    $Renderer.Dirty = $false
}

function InitWin-MoveNativeOutputCursorPosition {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][int] $Row,
        [Parameter(Mandatory)][int] $Column
    )

    $targetRow = [Math]::Max(0, $Row)
    $rowChanged = $targetRow -ne $Renderer.CursorRow
    if ($rowChanged) {
        if ($Renderer.Line.Count -gt 0) {
            InitWin-CommitNativeOutputLine -Renderer $Renderer
        } elseif ($Renderer.HasRenderedDynamicLine) {
            InitWin-CommitNativeOutputLine -Renderer $Renderer
        }
        while ($targetRow -gt $Renderer.CursorRow) {
            InitWin-CommitNativeOutputLine -Renderer $Renderer -ExplicitBlank
        }
        $Renderer.CursorRow = $targetRow
        $Renderer.Line.Clear()
        $Renderer.HasRenderedLine = $false
        $Renderer.HasRenderedDynamicLine = $false
        $Renderer.LastRenderedLineText = $null
        $Renderer.LineIsDynamic = $false
        $Renderer.LineHasCarriageReturn = $false
        $Renderer.PendingCarriageReturn = $false
        $Renderer.Dirty = $false
    }
    $Renderer.CursorColumn = [Math]::Max(0, $Column)
}

function InitWin-CompleteNativeOutputLine {
    param([Parameter(Mandatory)][object] $Renderer)

    if ($Renderer.PendingCarriageReturn) {
        $Renderer.PendingCarriageReturn = $false
        if ($Renderer.Line.Count -gt 0) {
            InitWin-CommitNativeOutputLine -Renderer $Renderer
            return
        }
    }

    if ($Renderer.Line.Count -gt 0) {
        InitWin-CommitNativeOutputLine -Renderer $Renderer
        return
    }

    if ($Renderer.HasRenderedDynamicLine) {
        InitWin-CommitNativeOutputLine -Renderer $Renderer
    }
}

function InitWin-WriteNativeOutputCharacter {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][char] $Character
    )

    while ($Renderer.Line.Count -lt $Renderer.CursorColumn) {
        $Renderer.Line.Add([char] 32)
    }
    if ($Renderer.CursorColumn -lt $Renderer.Line.Count) {
        $Renderer.Line[$Renderer.CursorColumn] = $Character
    } else {
        $Renderer.Line.Add($Character)
    }
    $Renderer.CursorColumn++
    $Renderer.Dirty = $true
}

function InitWin-InsertNativeOutputCharacters {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][int] $Count
    )

    while ($Renderer.Line.Count -lt $Renderer.CursorColumn) {
        $Renderer.Line.Add([char] 32)
    }
    for ($i = 0; $i -lt $Count; $i++) {
        $Renderer.Line.Insert($Renderer.CursorColumn, [char] 32)
    }
    $Renderer.Dirty = $true
}

function InitWin-DeleteNativeOutputCharacters {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][int] $Count
    )

    if ($Renderer.CursorColumn -lt $Renderer.Line.Count) {
        $deleteCount = [Math]::Min($Count, $Renderer.Line.Count - $Renderer.CursorColumn)
        if ($deleteCount -gt 0) { $Renderer.Line.RemoveRange($Renderer.CursorColumn, $deleteCount) }
    }
    $Renderer.Dirty = $true
}

function InitWin-EraseNativeOutputCharacters {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [Parameter(Mandatory)][int] $Count
    )

    $endColumn = $Renderer.CursorColumn + $Count
    while ($Renderer.Line.Count -lt $endColumn) {
        $Renderer.Line.Add([char] 32)
    }
    for ($i = $Renderer.CursorColumn; $i -lt $endColumn; $i++) {
        $Renderer.Line[$i] = [char] 32
    }
    $Renderer.Dirty = $true
}

function InitWin-ApplyNativeOutputCsi {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [AllowEmptyString()]
        [Parameter(Mandatory)][string] $ParameterText,
        [Parameter(Mandatory)][char] $Final
    )

    $cleanParameterText = $ParameterText -replace '^[?<=>]+', ''
    $parameters = @()
    if ($cleanParameterText.Length -gt 0) {
        foreach ($part in ($cleanParameterText -split '[;:]')) {
            if ($part -match '^\d+$') {
                $parameters += [int] $part
            } else {
                $parameters += 0
            }
        }
    }

    if ($Final -ceq 'K') {
        $mode = if ($parameters.Count -gt 0) { $parameters[0] } else { 0 }
        if ($mode -eq 0) {
            if ($Renderer.CursorColumn -lt $Renderer.Line.Count) {
                $Renderer.Line.RemoveRange($Renderer.CursorColumn, $Renderer.Line.Count - $Renderer.CursorColumn)
            }
        } elseif ($mode -eq 1) {
            $clearEnd = [Math]::Min($Renderer.CursorColumn, $Renderer.Line.Count - 1)
            if ($clearEnd -ge 0) {
                for ($i = 0; $i -le $clearEnd; $i++) { $Renderer.Line[$i] = [char] 32 }
            }
        } else {
            $Renderer.Line.Clear()
        }
        if (($Renderer.Line.Count -eq 0) -and (-not $Renderer.LineHasCarriageReturn)) {
            $Renderer.LineIsDynamic = $false
        }
        $Renderer.Dirty = $true
        return
    }

    if ($Final -ceq 'J') {
        if (($parameters.Count -eq 0) -or ($parameters[0] -ne 1)) {
            if ($Renderer.CursorColumn -lt $Renderer.Line.Count) {
                $Renderer.Line.RemoveRange($Renderer.CursorColumn, $Renderer.Line.Count - $Renderer.CursorColumn)
            }
            $Renderer.Dirty = $true
        }
        return
    }

    if ($Final -ceq '@') {
        $count = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        InitWin-InsertNativeOutputCharacters -Renderer $Renderer -Count $count
        return
    }

    if ($Final -ceq 'P') {
        $count = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        InitWin-DeleteNativeOutputCharacters -Renderer $Renderer -Count $count
        return
    }

    if ($Final -ceq 'X') {
        $count = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        InitWin-EraseNativeOutputCharacters -Renderer $Renderer -Count $count
        return
    }

    if (($Final -ceq 'G') -or (([int][char] $Final) -eq 0x60)) {
        $column = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        $Renderer.CursorColumn = $column - 1
        return
    }

    if (($Final -ceq 'C') -or ($Final -ceq 'D')) {
        $offset = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        if ($Final -ceq 'C') {
            $Renderer.CursorColumn += $offset
        } else {
            $Renderer.CursorColumn = [Math]::Max(0, $Renderer.CursorColumn - $offset)
        }
        return
    }

    if (($Final -ceq 'H') -or ($Final -ceq 'f')) {
        $row = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        $column = if (($parameters.Count -gt 1) -and ($parameters[1] -gt 0)) { $parameters[1] } else { 1 }
        InitWin-MoveNativeOutputCursorPosition -Renderer $Renderer -Row ($row - 1) -Column ($column - 1)
        return
    }

    if ($Final -ceq 'd') {
        $row = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        InitWin-MoveNativeOutputCursorPosition -Renderer $Renderer -Row ($row - 1) -Column $Renderer.CursorColumn
        return
    }

    if (($Final -ceq 'A') -or ($Final -ceq 'B')) {
        $offset = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        $row = if ($Final -ceq 'A') { $Renderer.CursorRow - $offset } else { $Renderer.CursorRow + $offset }
        InitWin-MoveNativeOutputCursorPosition -Renderer $Renderer -Row $row -Column $Renderer.CursorColumn
        return
    }

    if (($Final -ceq 'E') -or ($Final -ceq 'F')) {
        $offset = if (($parameters.Count -gt 0) -and ($parameters[0] -gt 0)) { $parameters[0] } else { 1 }
        $row = if ($Final -ceq 'F') { $Renderer.CursorRow - $offset } else { $Renderer.CursorRow + $offset }
        InitWin-MoveNativeOutputCursorPosition -Renderer $Renderer -Row $row -Column 0
        return
    }

    if ($Final -ceq 's') {
        $Renderer.SavedCursorRow = $Renderer.CursorRow
        $Renderer.SavedCursorColumn = $Renderer.CursorColumn
        return
    }

    if ($Final -ceq 'u') {
        InitWin-MoveNativeOutputCursorPosition -Renderer $Renderer -Row $Renderer.SavedCursorRow -Column $Renderer.SavedCursorColumn
    }
}

function InitWin-WriteNativeOutputText {
    param(
        [Parameter(Mandatory)][object] $Renderer,
        [AllowEmptyString()]
        [AllowNull()][string] $Text
    )

    if ($null -eq $Text) { return }
    $inputText = $Renderer.PendingText + $Text
    $Renderer.PendingText = ''

    for ($i = 0; $i -lt $inputText.Length; $i++) {
        $char = $inputText[$i]

        if ($Renderer.PendingCarriageReturn) {
            if ($char -eq [char] 10) {
                $Renderer.PendingCarriageReturn = $false
                InitWin-CommitNativeOutputLine -Renderer $Renderer -ExplicitBlank
                continue
            }

            if ($char -ne [char] 27) {
                InitWin-ResolveNativeOutputPendingCarriageReturn -Renderer $Renderer
            }
        }

        if ($char -eq [char] 27) {
            if (($i + 1) -ge $inputText.Length) {
                $Renderer.PendingText = $inputText.Substring($i)
                break
            }

            if ($inputText[$i + 1] -eq '[') {
                $sequenceStart = $i + 2
                $sequenceEnd = $sequenceStart
                while ($sequenceEnd -lt $inputText.Length) {
                    $finalCode = [int][char] $inputText[$sequenceEnd]
                    if (($finalCode -ge 0x40) -and ($finalCode -le 0x7E)) { break }
                    $sequenceEnd++
                }
                if ($sequenceEnd -ge $inputText.Length) {
                    $Renderer.PendingText = $inputText.Substring($i)
                    break
                }

                $parameterText = $inputText.Substring($sequenceStart, $sequenceEnd - $sequenceStart)
                $final = $inputText[$sequenceEnd]
                if ($Renderer.PendingCarriageReturn -and (-not (InitWin-TestNativeOutputCsiCanPrecedeLineFeed -ParameterText $parameterText -Final $final))) {
                    InitWin-ResolveNativeOutputPendingCarriageReturn -Renderer $Renderer
                }

                InitWin-ApplyNativeOutputCsi `
                    -Renderer $Renderer `
                    -ParameterText $parameterText `
                    -Final $final
                $i = $sequenceEnd
                continue
            }

            if ($inputText[$i + 1] -eq ']') {
                $sequenceEnd = $i + 2
                $isComplete = $false
                while ($sequenceEnd -lt $inputText.Length) {
                    if ($inputText[$sequenceEnd] -eq [char] 7) {
                        $isComplete = $true
                        break
                    }
                    if (($inputText[$sequenceEnd] -eq [char] 27) -and (($sequenceEnd + 1) -lt $inputText.Length) -and ($inputText[$sequenceEnd + 1] -eq [char] 92)) {
                        $sequenceEnd++
                        $isComplete = $true
                        break
                    }
                    $sequenceEnd++
                }
                if (-not $isComplete) {
                    $Renderer.PendingText = $inputText.Substring($i)
                    break
                }

                $i = $sequenceEnd
                continue
            }

            if ($inputText[$i + 1] -eq '7') {
                $Renderer.SavedCursorColumn = $Renderer.CursorColumn
                $i++
                continue
            }

            if ($inputText[$i + 1] -eq '8') {
                $Renderer.CursorColumn = [Math]::Max(0, $Renderer.SavedCursorColumn)
                $i++
                continue
            }

            $i++
            continue
        }

        if ($char -eq [char] 13) {
            $Renderer.PendingCarriageReturn = $true
            continue
        }

        if ($char -eq [char] 10) {
            InitWin-CommitNativeOutputLine -Renderer $Renderer -ExplicitBlank
            continue
        }

        if ($char -eq [char] 8) {
            $Renderer.CursorColumn = [Math]::Max(0, $Renderer.CursorColumn - 1)
            continue
        }

        if ($char -ne [char] 0) {
            InitWin-WriteNativeOutputCharacter -Renderer $Renderer -Character $char
        }
    }

    InitWin-RenderNativeOutputLine -Renderer $Renderer
}

function InitWin-ReadNativeOutputStream {
    param(
        [Parameter(Mandatory)][System.IO.StreamReader] $Reader,
        [Parameter(Mandatory)][char[]] $Buffer
    )

    $Reader.ReadAsync($Buffer, 0, $Buffer.Length)
}

function InitWin-ReadNativeOutputByteStream {
    param(
        [Parameter(Mandatory)][System.IO.Stream] $Stream,
        [Parameter(Mandatory)][byte[]] $Buffer
    )

    $Stream.ReadAsync($Buffer, 0, $Buffer.Length)
}

function InitWin-InvokeNativeWithPseudoConsole {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory)][object] $Renderer
    )

    InitWin-EnsurePseudoConsoleType
    $quotedFilePath = InitWin-QuoteNativeArgument -Argument $FilePath
    $joinedArguments = InitWin-JoinNativeArguments -Arguments $Arguments
    $commandLine = if ($joinedArguments) { "$quotedFilePath $joinedArguments" } else { $quotedFilePath }
    $workingDirectory = (Get-Location).ProviderPath
    $columns = $Renderer.Columns
    $rows = [Math]::Max(10, [Console]::WindowHeight)

    $process = [InitWin.PseudoConsoleProcess]::new($commandLine, $workingDirectory, [int16] $columns, [int16] $rows)
    $buffer = New-Object byte[] 4096
    $decoder = [System.Text.Encoding]::UTF8.GetDecoder()
    $chars = New-Object char[] ([System.Text.Encoding]::UTF8.GetMaxCharCount($buffer.Length))
    $readTask = InitWin-ReadNativeOutputByteStream -Stream $process.OutputStream -Buffer $buffer
    $closedConsole = $false

    try {
        while ($null -ne $readTask) {
            if ($readTask.Wait(50)) {
                $byteCount = $readTask.Result
                if ($byteCount -gt 0) {
                    $charCount = $decoder.GetChars($buffer, 0, $byteCount, $chars, 0, $false)
                    if ($charCount -gt 0) {
                        InitWin-WriteNativeOutputText -Renderer $Renderer -Text ([string]::new($chars, 0, $charCount))
                    }
                    $readTask = InitWin-ReadNativeOutputByteStream -Stream $process.OutputStream -Buffer $buffer
                    continue
                }

                $remainingChars = New-Object char[] 16
                $remainingCharCount = $decoder.GetChars([byte[]]::new(0), 0, 0, $remainingChars, 0, $true)
                if ($remainingCharCount -gt 0) {
                    InitWin-WriteNativeOutputText -Renderer $Renderer -Text ([string]::new($remainingChars, 0, $remainingCharCount))
                }
                $readTask = $null
                continue
            }

            if ((-not $closedConsole) -and $process.HasExited) {
                $process.CloseConsole()
                $closedConsole = $true
            }
        }

        if (-not $closedConsole) {
            $exitCode = $process.WaitForExit()
            $process.CloseConsole()
            $closedConsole = $true
        } else {
            $exitCode = $process.WaitForExit()
        }
    } finally {
        $process.Dispose()
    }

    $exitCode
}

function InitWin-InvokeNativeWithRedirectedOutput {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory)][object] $Renderer
    )

    $joinedArguments = InitWin-JoinNativeArguments -Arguments $Arguments
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $joinedArguments
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.StandardOutputEncoding = [Console]::OutputEncoding
    $startInfo.StandardErrorEncoding = [Console]::OutputEncoding

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void] $process.Start()

    $stdoutBuffer = New-Object char[] 1024
    $stderrBuffer = New-Object char[] 1024
    $stdoutTask = InitWin-ReadNativeOutputStream -Reader $process.StandardOutput -Buffer $stdoutBuffer
    $stderrTask = InitWin-ReadNativeOutputStream -Reader $process.StandardError -Buffer $stderrBuffer

    while (($null -ne $stdoutTask) -or ($null -ne $stderrTask)) {
        $tasks = @()
        if ($null -ne $stdoutTask) { $tasks += $stdoutTask }
        if ($null -ne $stderrTask) { $tasks += $stderrTask }

        $completedIndex = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]] $tasks, 100)
        if ($completedIndex -lt 0) { continue }

        $completedTask = $tasks[$completedIndex]
        if ([object]::ReferenceEquals($completedTask, $stdoutTask)) {
            $count = $stdoutTask.Result
            if ($count -gt 0) {
                InitWin-WriteNativeOutputText -Renderer $Renderer -Text ([string]::new($stdoutBuffer, 0, $count))
                $stdoutTask = InitWin-ReadNativeOutputStream -Reader $process.StandardOutput -Buffer $stdoutBuffer
            } else {
                $stdoutTask = $null
            }
            continue
        }

        $count = $stderrTask.Result
        if ($count -gt 0) {
            InitWin-WriteNativeOutputText -Renderer $Renderer -Text ([string]::new($stderrBuffer, 0, $count))
            $stderrTask = InitWin-ReadNativeOutputStream -Reader $process.StandardError -Buffer $stderrBuffer
        } else {
            $stderrTask = $null
        }
    }

    $process.WaitForExit()
    $process.ExitCode
}

function InitWin-InvokeNative {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string[]] $Arguments = @(),
        [switch] $IgnoreExitCode
    )

    $joinedArguments = InitWin-JoinNativeArguments -Arguments $Arguments
    $command = if ($joinedArguments) { "$FilePath $joinedArguments" } else { $FilePath }
    InitWin-WriteDetail $command -ForegroundColor DarkGray

    $renderer = InitWin-NewNativeOutputRenderer
    if ($renderer.UseVirtualTerminal -and (InitWin-TestPseudoConsoleAvailable)) {
        $exitCode = InitWin-InvokeNativeWithPseudoConsole -FilePath $FilePath -Arguments $Arguments -Renderer $renderer
    } else {
        $exitCode = InitWin-InvokeNativeWithRedirectedOutput -FilePath $FilePath -Arguments $Arguments -Renderer $renderer
    }
    InitWin-CompleteNativeOutputLine -Renderer $renderer

    if ($exitCode -ne 0) {
        if ($IgnoreExitCode) {
            InitWin-WriteDetail "exit code: $exitCode" -ForegroundColor Yellow
            return
        }
        throw "Native command failed with exit code $exitCode`: $command"
    }
}
