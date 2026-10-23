# =============================================================================
# console.ps1 —— 给游戏发控制台指令（自己打字，不用人手）
#
#   powershell -File tools\console.ps1 "giveitem c118"
#   powershell -File tools\console.ps1 "debug 3|giveitem c417" -Shot
#   powershell -File tools\console.ps1 "spawn 10.1" -ShotPath _logs\c1.png
#
# 多条指令用 **竖线 |** 分隔（按顺序执行，每条自动回车）。
#
# 前置：游戏已在跑、且已进局（控制台只在局内有用）。
#       options.ini 的 EnableDebugConsole=1 已开。
#
# 参数：
#   -Commands      一条或多条指令，用 | 分隔
#   -Settle <ms>   每条之后等待，默认 350
#   -KeepOpen      执行完不关控制台（默认关掉，免得截图被挡）
#   -Shot          关掉控制台后截一张图
#   -ShotPath <p>  截图路径（默认 _logs\console-<时间>.png）
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Commands,
    [int]$Settle = 350,
    [switch]$KeepOpen,
    [switch]$Shot,
    [string]$ShotPath
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "_paths.ps1")
. (Join-Path $here "_win.ps1")

$list = @($Commands -split "\|" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
if ($list.Count -eq 0) {
    Write-Host "没有可执行的指令" -ForegroundColor Red
    exit 2
}

$w = Get-GameWindow
if (-not $w) {
    Write-Host "游戏没在跑（找不到 isaac-ng 窗口）" -ForegroundColor Red
    exit 2
}
Write-Host ("  窗口: 0x{0:X}" -f [int64]$w.Handle)

if (-not (Focus-Window $w)) {
    Write-Host "拿不到前台，中止（不动键盘）" -ForegroundColor Red
    exit 3
}
Start-Sleep -Milliseconds 200

# 1) 开控制台
Send-GameKey GRAVE
Start-Sleep -Milliseconds 400

# 1.5) 容错：如果控制台本来就是开着的，上面那个 ~ 会作为字符打进输入框；
#      而且上一轮的残留可能还在输入行里。按 40 次退格清场（空行时退格无副作用）。
Send-GameKey BACKSPACE -Repeat 40 -GapMs 12
Start-Sleep -Milliseconds 150

# 2) 逐条打
#    ENTER 要按**两下**：Isaac 控制台有自动补全，第一下是在"选中候选"，
#    第二下才真正执行（没有候选时第二下只是空回车，无害）。
foreach ($c in $list) {
    Write-Host ("  > " + $c) -ForegroundColor Cyan
    Send-GameText $c
    Start-Sleep -Milliseconds 120
    Send-GameKey ENTER
    Start-Sleep -Milliseconds 150
    Send-GameKey ENTER
    Start-Sleep -Milliseconds $Settle
}

# 3) 关控制台（用 ESC：`~` 会被输入框吃掉，关不掉）
if (-not $KeepOpen) {
    Send-GameKey ESCAPE
    Start-Sleep -Milliseconds 300
}

# 4) 截图
if ($Shot -or $ShotPath) {
    if (-not $ShotPath) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $ShotPath = Join-Path $script:RepoRoot ("_logs\console-$stamp.png")
    }
    $dir = Split-Path -Parent $ShotPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $full = Save-WindowShot $w $ShotPath
    Write-Host ("  [截图] " + $full) -ForegroundColor Green
}

Write-Host "完成" -ForegroundColor Green
exit 0
