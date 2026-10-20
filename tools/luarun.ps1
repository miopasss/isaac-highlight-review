# =============================================================================
# luarun.ps1 —— 用游戏自带的 Lua5.4.dll 执行 Lua 文件（离线单测）
#
# 必须用 **32 位** PowerShell 运行（游戏的 Lua5.4.dll 是 x86）：
#   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile ^
#       -ExecutionPolicy Bypass -File tools\luarun.ps1 <file.lua>
#
# 被执行的脚本若 return 一个字符串，会被打印出来；返回 nil 打印 "(nil)"。
# =============================================================================
param([Parameter(Mandatory = $true)][string]$File)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
$GameDir = $IsaacDir
$ProjectRoot = Split-Path $PSScriptRoot -Parent   # tools 的上一级
$Dll = Join-Path $GameDir "Lua5.4.dll"

if (-not (Test-Path $Dll)) { Write-Host "找不到 $Dll"; exit 2 }
if ([IntPtr]::Size -ne 4) { Write-Host "必须用 32 位 PowerShell（当前 $([IntPtr]::Size * 8) 位）"; exit 2 }
if (-not (Test-Path $File)) { Write-Host "找不到 $File"; exit 2 }

$File = (Resolve-Path $File).Path
$env:PATH = "$GameDir;$env:PATH"
$escaped = $Dll.Replace('\', '\\')

$src = @"
using System;
using System.Runtime.InteropServices;
public static class LuaRun {
    const string D = "$escaped";
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr luaL_newstate();
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern void luaL_openlibs(IntPtr L);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern int luaL_loadfilex(IntPtr L, string filename, string mode);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern int lua_pcallk(IntPtr L, int nargs, int nresults, int errfunc, IntPtr ctx, IntPtr k);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr lua_tolstring(IntPtr L, int idx, out UIntPtr len);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern void lua_settop(IntPtr L, int idx);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern int lua_type(IntPtr L, int idx);

    static string Top(IntPtr L) {
        UIntPtr len; IntPtr p = lua_tolstring(L, -1, out len);
        return p == IntPtr.Zero ? "(nil)" : Marshal.PtrToStringAnsi(p);
    }

    public static string Exec(string path) {
        IntPtr L = luaL_newstate();
        if (L == IntPtr.Zero) return "ERR: newstate";
        luaL_openlibs(L);
        int rc = luaL_loadfilex(L, path, null);
        if (rc != 0) { string e = Top(L); lua_settop(L, 0); return "LOAD FAIL: " + e; }
        rc = lua_pcallk(L, 0, 1, 0, IntPtr.Zero, IntPtr.Zero);
        if (rc != 0) { string e = Top(L); lua_settop(L, 0); return "RUN FAIL: " + e; }
        string r = Top(L);
        lua_settop(L, 0);
        return r;
    }
}
"@
# 把路径传给 Lua（Lua 里不准硬编码路径）
$env:HLR_ROOT = $ProjectRoot
$env:HLR_DATA = Join-Path $IsaacDir "data\highlight-review"

# 环境变量传不进进程内的 LuaJIT（MSVC 的 getenv 读启动缓存的 _environ），
# 所以额外写一个 Lua 文件，脚本用 loadfile 读它。
$logsDir = Join-Path $ProjectRoot "_logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$pathsLua = Join-Path $logsDir ".hlr_paths.lua"
$rootLua  = $ProjectRoot.Replace("\", "/")
$dataLua  = (Join-Path $IsaacDir "data\highlight-review").Replace("\", "/")
$pathsBody = "return { root = [[" + $rootLua + "/]], data = [[" + $dataLua + "/]] }"
[System.IO.File]::WriteAllText($pathsLua, $pathsBody, (New-Object System.Text.UTF8Encoding($false)))

Add-Type -TypeDefinition $src

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$result = [LuaRun]::Exec($File)
Write-Host $result
if ($result -like "*FAIL*") { exit 1 }
exit 0
