# =============================================================================
# luacheck.ps1 —— 用游戏自带的 Lua5.4.dll 做语法校验（无需安装 Lua）
#
# 必须用 **32 位** PowerShell 运行（游戏的 Lua5.4.dll 是 x86）：
#   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile ^
#       -ExecutionPolicy Bypass -File tools\luacheck.ps1
#
# 用法：luacheck.ps1 [文件或目录...]   默认检查 ..\mod
# =============================================================================
param([string[]]$Paths)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
$GameDir = $IsaacDir
$Dll     = Join-Path $GameDir "Lua5.4.dll"

if (-not (Test-Path $Dll)) { Write-Host "找不到 $Dll"; exit 2 }
if ([IntPtr]::Size -ne 4) {
    Write-Host "本脚本必须用 32 位 PowerShell 运行（当前进程位数: $([IntPtr]::Size * 8)）"
    exit 2
}

$env:PATH = "$GameDir;$env:PATH"
$escaped = $Dll.Replace('\', '\\')
$src = @"
using System;
using System.Runtime.InteropServices;
public static class LuaHost {
    const string D = "$escaped";
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr luaL_newstate();
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern int luaL_loadbufferx(IntPtr L, byte[] buff, UIntPtr sz, string name, string mode);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr lua_tolstring(IntPtr L, int idx, out UIntPtr len);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern void lua_settop(IntPtr L, int idx);
    public static string Check(string path) {
        byte[] bytes = System.IO.File.ReadAllBytes(path);
        IntPtr L = luaL_newstate();
        if (L == IntPtr.Zero) return "ERR: luaL_newstate failed";
        int rc = luaL_loadbufferx(L, bytes, (UIntPtr)(ulong)bytes.Length, "@" + path, "t");
        if (rc == 0) { lua_settop(L, 0); return "OK"; }
        UIntPtr len; IntPtr p = lua_tolstring(L, -1, out len);
        string msg = p == IntPtr.Zero ? "unknown error" : Marshal.PtrToStringAnsi(p);
        lua_settop(L, 0);
        return "FAIL: " + msg;
    }
}
"@
Add-Type -TypeDefinition $src

if (-not $Paths -or $Paths.Count -eq 0) {
      $base = (Split-Path $PSScriptRoot -Parent)
      $Paths = @((Join-Path $base "mod-review"), (Join-Path $base "mod-rating"), (Join-Path $base "shared"))
}

$files = @()
foreach ($p in $Paths) {
    if (Test-Path $p -PathType Container) {
        $files += Get-ChildItem -Path $p -Filter *.lua -Recurse -File | ForEach-Object { $_.FullName }
    } elseif (Test-Path $p) {
        $files += (Resolve-Path $p).Path
    } else {
        Write-Host "跳过（不存在）: $p"
    }
}

if ($files.Count -eq 0) { Write-Host "没有找到 .lua 文件"; exit 2 }

$fail = 0
foreach ($f in $files) {
    $res = [LuaHost]::Check($f)
    $name = $f.Replace((Split-Path $PSScriptRoot -Parent), '.').Replace('\', '/')
    if ($res -eq "OK") {
        Write-Host ("  OK    {0}" -f $name) -ForegroundColor DarkGray
    } else {
        Write-Host ("  {0,-5} {1}" -f "FAIL", $name) -ForegroundColor Red
        Write-Host ("        {0}" -f $res) -ForegroundColor Red
        $fail++
    }
}
Write-Host ""
Write-Host ("检查 {0} 个文件，失败 {1} 个" -f $files.Count, $fail)
exit ([int]($fail -gt 0))
