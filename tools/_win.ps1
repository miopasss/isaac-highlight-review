# =============================================================================
# _win.ps1 —— 窗口/输入/截图三件套（给 verify.ps1 用的底层）
#
# 为什么要这么底层：
#   游戏是 SDL2 + Direct3D，SendKeys 往窗口"贴"按键不一定被收；
#   用 SendInput 发**扫描码**（不是虚拟键码）最接近真实键盘。
#   另外游戏切全屏/换分辨率时会重建窗口句柄，Process.MainWindowHandle 会变 0，
#   所以这里用 EnumWindows 按 PID 枚举，比 MainWindowHandle 稳。
#
# 注意：本文件必须是 UTF-8 with BOM（Windows PowerShell 5.1 只认带 BOM 的 UTF-8，
#       否则中文注释会被按 GBK 解析，整份脚本语法炸掉）。
#
# 用法：在脚本开头 dot-source 它
#   . "$PSScriptRoot\_win.ps1"
#   $w = Get-GameWindow
#   Focus-Window $w
#   Send-GameKey F5
#   Save-WindowShot $w "D:\x\shot.png"
# =============================================================================

Add-Type -AssemblyName System.Drawing

if (-not ("IsaacWin32" -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class IsaacWin32
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT
    {
        public int length, flags, showCmd;
        public POINT ptMinPosition, ptMaxPosition;
        public RECT rcNormalPosition;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public InputUnion U; }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL, wParamH; }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint n, INPUT[] inputs, int size);

    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint KEYEVENTF_SCANCODE = 0x0008;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

    public static uint Key(ushort vk, ushort scan, bool up, bool extended)
    {
        INPUT[] one = new INPUT[1];
        one[0].type = INPUT_KEYBOARD;
        one[0].U.ki.wVk = vk;
        one[0].U.ki.wScan = scan;
        one[0].U.ki.dwFlags = KEYEVENTF_SCANCODE
            | (up ? KEYEVENTF_KEYUP : 0)
            | (extended ? KEYEVENTF_EXTENDEDKEY : 0);
        return SendInput(1, one, Marshal.SizeOf(typeof(INPUT)));
    }

    public static IntPtr[] WindowsOfPid(uint pid)
    {
        List<IntPtr> found = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            uint p;
            GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }

    public static string Title(IntPtr h)
    {
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString();
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);

    public static string ClassName(IntPtr h)
    {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, sb.Capacity);
        return sb.ToString();
    }

    public static int Area(IntPtr h)
    {
        RECT r;
        if (!GetWindowRect(h, out r)) return 0;
        return Math.Max(0, r.Right - r.Left) * Math.Max(0, r.Bottom - r.Top);
    }

    // 抢占前台的经典套路：先把自己挂到当前前台线程上，再 SetForegroundWindow。
    // 直接 SetForegroundWindow 会被 Windows 的前台锁拦住（返回 true 但不生效）。
    public static bool Force(IntPtr h)
    {
        if (IsIconic(h)) ShowWindow(h, 9);              // SW_RESTORE
        IntPtr fg = GetForegroundWindow();
        uint pid;
        uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out pid);
        uint myThread = GetCurrentThreadId();
        bool attached = false;
        if (fgThread != 0 && fgThread != myThread) attached = AttachThreadInput(myThread, fgThread, true);
        bool ok = SetForegroundWindow(h);
        BringWindowToTop(h);
        if (attached) AttachThreadInput(myThread, fgThread, false);
        return ok;
    }
}
"@
}

# ---------------------------------------------------------------- 窗口

function Get-GameWindow {
    param([string]$ProcessName = "isaac-ng")
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return $null }

    # 优先按 PID 枚举可见顶层窗口，取面积最大的那个（游戏窗口一定最大）
    $best = [IntPtr]::Zero
    $bestArea = 0
    foreach ($h in [IsaacWin32]::WindowsOfPid([uint32]$p.Id)) {
        $a = [IsaacWin32]::Area($h)
        if ($a -gt $bestArea) { $bestArea = $a; $best = $h }
    }
    if ($best -eq [IntPtr]::Zero -and $p.MainWindowHandle -ne 0) {
        $best = $p.MainWindowHandle
        $bestArea = [IsaacWin32]::Area($best)
    }
    if ($best -eq [IntPtr]::Zero) {
        # 进程活着但还没有窗口（正在启动 / 正在关闭）
        return [pscustomobject]@{
            Process  = $p
            Handle   = [IntPtr]::Zero
            Title    = ""
            Pid      = $p.Id
            Area     = 0
            NoWindow = $true
        }
    }
    return [pscustomobject]@{
        Process  = $p
        Handle   = $best
        Title    = [IsaacWin32]::Title($best)
        Pid      = $p.Id
        Area     = $bestArea
        NoWindow = $false
    }
}

function Get-WindowState {
    param($Window)
    $wp = New-Object IsaacWin32+WINDOWPLACEMENT
    $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf([type]([IsaacWin32+WINDOWPLACEMENT]))
    [void][IsaacWin32]::GetWindowPlacement($Window.Handle, [ref]$wp)
    $names = @{ 0 = "hidden"; 1 = "normal"; 2 = "minimized"; 3 = "maximized" }
    $name = if ($names.ContainsKey($wp.showCmd)) { $names[$wp.showCmd] } else { "cmd$($wp.showCmd)" }
    $rc = New-Object IsaacWin32+RECT
    [void][IsaacWin32]::GetWindowRect($Window.Handle, [ref]$rc)
    return [pscustomobject]@{
        ShowCmd      = $wp.showCmd
        State        = $name
        Rect         = ("{0},{1} {2}x{3}" -f $rc.Left, $rc.Top, ($rc.Right - $rc.Left), ($rc.Bottom - $rc.Top))
        IsForeground = ([IsaacWin32]::GetForegroundWindow() -eq $Window.Handle)
    }
}

function Get-ForegroundInfo {
    $h = [IsaacWin32]::GetForegroundWindow()
    $fgPid = [uint32]0
    [void][IsaacWin32]::GetWindowThreadProcessId($h, [ref]$fgPid)
    return [pscustomobject]@{
        Handle    = $h
        Pid       = $fgPid
        Class     = [IsaacWin32]::ClassName($h)
        Title     = [IsaacWin32]::Title($h)
    }
}

# 抢前台。Windows 的前台锁 + 任务栏浮层（Shell_Flyout）都会让 SetForegroundWindow 白给，
# 所以这里分三步：常规抢占 → 最小化再还原 → 给浮层发 ESC 让它自己退场。
function Focus-Window {
    param($Window, [switch]$Quiet, [int]$Tries = 3)
    if (-not $Window) { throw "没有窗口可聚焦" }
    if ($Window.Handle -eq [IntPtr]::Zero) { return $false }

    for ($i = 1; $i -le $Tries; $i++) {
        [void][IsaacWin32]::Force($Window.Handle)
        Start-Sleep -Milliseconds 400
        if ([IsaacWin32]::GetForegroundWindow() -eq $Window.Handle) {
            if (-not $Quiet) { Write-Host "  [窗口] 已在前台" -ForegroundColor DarkGray }
            return $true
        }

        $fg = Get-ForegroundInfo
        $fgClass = "$($fg.Class)"
        if ($fgClass -match 'Shell_Flyout|CoreWindow|Windows\.UI|TaskListThumbnail') {
            # 任务栏浮层霸着前台：SendInput 的 ESC 不需要前台权限，能把它关掉
            Send-GameKey ESCAPE
            Start-Sleep -Milliseconds 350
        } elseif ($i -eq 2) {
            # 最小化再还原，通常能重新拿到前台
            [void][IsaacWin32]::ShowWindow($Window.Handle, 6)
            Start-Sleep -Milliseconds 250
            [void][IsaacWin32]::ShowWindow($Window.Handle, 9)
            Start-Sleep -Milliseconds 250
        }
    }

    $fg = Get-ForegroundInfo
    if (-not $Quiet) {
        Write-Host ("  [窗口] 提到前台失败（前台 class={0} hwnd=0x{1:X}）" -f $fg.Class, [int64]$fg.Handle) -ForegroundColor Yellow
    }
    return $false
}

function Get-ClientRectScreen {
    param($Window)
    $r = New-Object IsaacWin32+RECT
    if (-not [IsaacWin32]::GetClientRect($Window.Handle, [ref]$r)) { throw "GetClientRect 失败" }
    $pt = New-Object IsaacWin32+POINT
    $pt.X = 0; $pt.Y = 0
    [void][IsaacWin32]::ClientToScreen($Window.Handle, [ref]$pt)
    return [pscustomobject]@{
        X      = $pt.X
        Y      = $pt.Y
        Width  = $r.Right - $r.Left
        Height = $r.Bottom - $r.Top
    }
}

function Save-WindowShot {
    param($Window, [string]$Path, [switch]$NoFocus, [switch]$PrintWindowMode)
    if (-not $Window) { $Window = Get-GameWindow }
    if (-not $Window -or $Window.Handle -eq [IntPtr]::Zero) { throw "没找到游戏窗口" }
    if (-not $NoFocus) { [void](Focus-Window $Window -Quiet) }
    Start-Sleep -Milliseconds 250
    $rc = Get-ClientRectScreen $Window
    if ($rc.Width -le 0 -or $rc.Height -le 0) { throw "窗口尺寸为 0（最小化了？）" }

    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $bmp = New-Object System.Drawing.Bitmap($rc.Width, $rc.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    if ($PrintWindowMode) {
        # PW_RENDERFULLCONTENT = 0x2：让窗口自己渲染到内存位图，即使被遮挡也能拿到
        $hdc = $g.GetHdc()
        [void][IsaacWin32]::PrintWindow($Window.Handle, $hdc, 2)
        $g.ReleaseHdc($hdc)
    } else {
        $g.CopyFromScreen($rc.X, $rc.Y, 0, 0, (New-Object System.Drawing.Size($rc.Width, $rc.Height)))
    }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    return (Get-Item $Path).FullName
}

# ---------------------------------------------------------------- 按键
# 扫描码表：只收这里用得到的键。扩展键（方向键区）要带 EXTENDEDKEY。
$script:KeyMap = @{
    "ESCAPE"    = @(0x01, 0x01, $false)
    "ENTER"     = @(0x0D, 0x1C, $false)
    "SPACE"     = @(0x20, 0x39, $false)
    "TAB"       = @(0x09, 0x0F, $false)
    "BACKSPACE" = @(0x08, 0x0E, $false)
    "UP"        = @(0x26, 0x48, $true)
    "DOWN"      = @(0x28, 0x50, $true)
    "LEFT"      = @(0x25, 0x4B, $true)
    "RIGHT"     = @(0x27, 0x4D, $true)
    "F1"        = @(0x70, 0x3B, $false)
    "F2"        = @(0x71, 0x3C, $false)
    "F3"        = @(0x72, 0x3D, $false)
    "F4"        = @(0x73, 0x3E, $false)
    "F5"        = @(0x74, 0x3F, $false)
    "F6"        = @(0x75, 0x40, $false)
    "F7"        = @(0x76, 0x41, $false)
    "F8"        = @(0x77, 0x42, $false)
    "F9"        = @(0x78, 0x43, $false)
    "F10"       = @(0x79, 0x44, $false)
    "F11"       = @(0x7A, 0x57, $false)
    "F12"       = @(0x7B, 0x58, $false)
    "GRAVE"     = @(0xC0, 0x29, $false)
    "W"         = @(0x57, 0x11, $false)
    "A"         = @(0x41, 0x1E, $false)
    "S"         = @(0x53, 0x1F, $false)
    "D"         = @(0x44, 0x20, $false)
    "E"         = @(0x45, 0x12, $false)
    "I"         = @(0x49, 0x17, $false)
    "Q"         = @(0x51, 0x10, $false)
    "R"         = @(0x52, 0x13, $false)
    "C"         = @(0x43, 0x2E, $false)
}

function Send-GameKey {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [int]$HoldMs = 60,
        [int]$Repeat = 1,
        [int]$GapMs = 120
    )
    $k = $Key.ToUpper()
    if (-not $script:KeyMap.ContainsKey($k)) { throw "没登记的按键：$Key（在 _win.ps1 的 KeyMap 里加）" }
    $vk, $scan, $ext = $script:KeyMap[$k]
    for ($i = 0; $i -lt $Repeat; $i++) {
        [void][IsaacWin32]::Key([uint16]$vk, [uint16]$scan, $false, [bool]$ext)
        Start-Sleep -Milliseconds $HoldMs
        [void][IsaacWin32]::Key([uint16]$vk, [uint16]$scan, $true, [bool]$ext)
        if ($i -lt $Repeat - 1) { Start-Sleep -Milliseconds $GapMs }
    }
    Start-Sleep -Milliseconds 80
}
