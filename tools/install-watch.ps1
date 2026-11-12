# =============================================================================
# install-watch.ps1 -- 把“可见的存档备份窗口”装到桌面 + 开机自启
#
#   powershell -File tools\install-watch.ps1            装（桌面 + 启动项，顺手停用旧计划任务）
#   powershell -File tools\install-watch.ps1 -Uninstall 卸
#   powershell -File tools\install-watch.ps1 -Status    看现在装了什么
#
# 生成的两个 .cmd 都是纯 ASCII（cmd 读文件用 OEM 代码页，中文会乱码），
# 中文全部由 PowerShell 窗口自己输出。
# =============================================================================
param(
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$KeepTask,     # 保留旧的隐藏计划任务 IsaacSaveBackup
    [switch]$NoDesktop,
    [switch]$NoStartup
)

$ErrorActionPreference = "Continue"
$TaskName = "IsaacSaveBackup"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$WatchPs1 = Join-Path $PSScriptRoot "save-watch.ps1"

$DesktopDir = [Environment]::GetFolderPath("Desktop")
$StartupDir = [Environment]::GetFolderPath("Startup")
$DesktopCmd = Join-Path $DesktopDir "以撒存档备份.cmd"
$StartupCmd = Join-Path $StartupDir "以撒存档备份（开机自启）.cmd"

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

function New-Launcher([string]$path) {
    $lines = @(
        "@echo off",
        "chcp 65001 >nul",
        "title Isaac Save Watch",
        "cd /d `"$RepoRoot`"",
        "powershell -NoProfile -ExecutionPolicy Bypass -File `"$WatchPs1`"",
        "echo.",
        "echo [watcher stopped] press any key to close this window",
        "pause >nul"
    )
    $text = ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($path, $text, [System.Text.Encoding]::ASCII)
}

function Remove-TaskIfAny {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Say ("已停用旧的隐藏计划任务 {0}（避免和窗口重复备份）" -f $TaskName) Yellow
    }
}

if ($Uninstall) {
    foreach ($p in @($DesktopCmd, $StartupCmd)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Say ("已删除 " + $p) Green }
    }
    Say "卸载完成（计划任务没动，要删用 backup-saves.ps1 -Uninstall）" Yellow
    exit 0
}

if ($Status) {
    Say ("仓库: {0}" -f $RepoRoot) Gray
    foreach ($p in @($DesktopCmd, $StartupCmd)) {
        $mark = if (Test-Path -LiteralPath $p) { "已安装" } else { "未安装" }
        Say ("{0}  {1}" -f $mark, $p) Gray
    }
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) { Say ("计划任务 {0}: {1}（与窗口同时跑会重复，建议删）" -f $TaskName, $t.State) Yellow }
    else { Say "计划任务未安装（正常：现在用窗口方案）" Gray }
    exit 0
}

# ---------------------------------------------------------------- 安装
if (-not (Test-Path -LiteralPath $WatchPs1)) { Say "缺少 save-watch.ps1" Red; exit 1 }

if (-not $NoDesktop) {
    New-Launcher $DesktopCmd
    Say ("桌面快捷方式: {0}" -f $DesktopCmd) Green
}
if (-not $NoStartup) {
    New-Launcher $StartupCmd
    Say ("开机自启:     {0}" -f $StartupCmd) Green
}
if (-not $KeepTask) { Remove-TaskIfAny }

Say ""
Say "用法：" White
Say "  · 双击桌面的「以撒存档备份」→ 打开可见的备份窗口"
Say "  · 登录后会自动开一个同样的窗口（关掉就停，再双击可重开）"
Say "  · 同一时间只会有一个窗口在跑（第二个会自己退出）"
