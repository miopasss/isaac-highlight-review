# =============================================================================
# play.ps1 —— 「启动游戏」的正确方式：先归档，再开游戏，退出后再归档一次
#
# 为什么需要它：游戏里的 mod 没法自己写文件（io 被沙箱移除），
# 所以"把存档备份出去"这件事只能由外部脚本代劳。
#
# 用法：
#   pwsh tools\play.ps1              归档 → 启动 REPENTOGONLauncher → 等退出 → 再归档
#   pwsh tools\play.ps1 -NoWait      归档 → 启动 → 立刻返回（不等游戏）
#   pwsh tools\play.ps1 -NoLaunch    只归档，不启动（用来验证）
#
# 也可以直接双击 tools\play.cmd
# =============================================================================
param(
    [switch]$NoWait,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
$Game = $IsaacDir
$Archive = Join-Path $PSScriptRoot "archive.ps1"

function Invoke-Archive([string]$why) {
    if (-not (Test-Path $Archive)) { Write-Host "找不到 archive.ps1，跳过备份" -ForegroundColor Yellow; return }
    Write-Host ("── 备份（{0}）" -f $why) -ForegroundColor DarkGray
    & $Archive
}

# 1) 启动前备份：把上一局留下的数据先收进永久档案
Invoke-Archive "启动前"

if ($NoLaunch) { Write-Host "`n-NoLaunch：不启动游戏。" -ForegroundColor DarkGray; exit 0 }

# 2) 启动（优先用 REPENTOGONLauncher，它会先检查版本）
$launcher = Join-Path $Game "REPENTOGONLauncher\REPENTOGONLauncher.exe"
$exe      = Join-Path $Game "isaac-ng.exe"
Write-Host ""
if (Test-Path $launcher) {
    Write-Host "启动 REPENTOGONLauncher ..." -ForegroundColor Cyan
    Start-Process -FilePath $launcher
} elseif (Test-Path $exe) {
    Write-Host "启动 isaac-ng.exe ..." -ForegroundColor Cyan
    Start-Process -FilePath $exe
} else {
    Write-Host "找不到游戏可执行文件：$Game" -ForegroundColor Red
    exit 2
}

# 不再等待游戏退出（只备份一次，在启动前）

# 只做启动前备份（作者要求：关游戏后不保存）
Write-Host "完成：已备份，游戏已启动。" -ForegroundColor Green
