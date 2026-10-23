# =============================================================================
# console.ps1 —— 给游戏发控制台指令（安全版：没确认控制台打开前**绝不打字**）
#
#   powershell -File tools\console.ps1 "giveitem c118"
#   powershell -File tools\console.ps1 "debug 3|giveitem c417" -Shot
#
# 多条指令用 **竖线 |** 分隔。
#
# ⚠️ 为什么要"确认打开"：Isaac 的控制台是按 ~ 切换的，而且 `restart`/`stage` 这类
# 改变游戏状态的命令会让控制台**自己关掉**。旧脚本只在开头按一次 ~，之后就一直打字，
# 控制台一旦关掉，字母就变成游戏操作（WASD 移动、E 用道具、ENTER 进菜单）—— 这是
# 2026-10-23 作者报告的"游戏内乱操作"的根因。
#
# 现在每条指令前都用像素探针确认控制台在（控制台标题条是蓝色，局内是棕色）；
# 打不开就**立即中止**，一个字符都不发。
#
# 参数：
#   -Commands      指令，多条用 | 分隔
#   -Settle <ms>   每条之后等待，默认 350
#   -KeepOpen      执行完不关控制台（默认关掉）
#   -Shot          关掉控制台后截图
#   -ShotPath <p>  截图路径
#   -NoProbe       跳过像素探针（**危险**，只在确认控制台已打开时用）
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Commands,
    [int]$Settle = 350,
    [switch]$KeepOpen,
    [switch]$Shot,
    [string]$ShotPath,
    [switch]$NoProbe
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "_paths.ps1")
. (Join-Path $here "_win.ps1")
Add-Type -AssemblyName System.Drawing

$list = @($Commands -split "\|" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
if ($list.Count -eq 0) { Write-Host "没有可执行的指令" -ForegroundColor Red; exit 2 }

$w = Get-GameWindow
if (-not $w) { Write-Host "游戏没在跑" -ForegroundColor Red; exit 2 }
Write-Host ("  窗口: 0x{0:X}" -f [int64]$w.Handle)

if (-not (Focus-Window $w)) {
    Write-Host "拿不到前台，中止（不动键盘）" -ForegroundColor Red
    exit 3
}
Start-Sleep -Milliseconds 150

# ---------------------------------------------------------------- 控制台开/关判定
# 控制台标题条是蓝色（B 明显大于 R）；局内同一位置是棕色/黑色（B≈R 或更小）。
# 采样点按窗口尺寸的百分比取，避免分辨率变化后失效。
function Test-ConsoleOpen {
    param($Win)
    $tmp = Join-Path $env:TEMP ("dsh-console-probe-{0}.png" -f $PID)
    try { Save-WindowShot $Win $tmp | Out-Null } catch { return $false }
    $bmp = $null
    try {
        $bmp = [System.Drawing.Bitmap]::FromFile($tmp)
        $W = $bmp.Width; $H = $bmp.Height
        $hit = 0; $tot = 0
        foreach ($xp in 0.08, 0.12, 0.16, 0.20, 0.24, 0.28, 0.32, 0.36) {
            foreach ($yp in 0.070, 0.083, 0.096) {
                $x = [int]($W * $xp); $y = [int]($H * $yp)
                if ($x -lt 0 -or $y -lt 0 -or $x -ge $W -or $y -ge $H) { continue }
                $c = $bmp.GetPixel($x, $y)
                $tot++
                if (($c.B - $c.R) -ge 30 -and $c.B -ge 80) { $hit++ }
            }
        }
        if ($tot -eq 0) { return $false }
        return ($hit / $tot) -ge 0.4
    } catch {
        return $false
    } finally {
        if ($bmp) { $bmp.Dispose() }
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
}

function Ensure-ConsoleOpen {
    param($Win)
    if ($NoProbe) {
        Send-GameKey GRAVE
        Start-Sleep -Milliseconds 350
        return $true
    }
    if (Test-ConsoleOpen $Win) { return $true }

    Send-GameKey GRAVE
    Start-Sleep -Milliseconds 350
    if (Test-ConsoleOpen $Win) {
        # 打开瞬间可能混进一个 ~ 字符，退格清掉（空行时无副作用）
        Send-GameKey BACKSPACE -Repeat 40 -GapMs 10
        Start-Sleep -Milliseconds 100
        return $true
    }
    Send-GameKey GRAVE          # 再试一次
    Start-Sleep -Milliseconds 350
    if (Test-ConsoleOpen $Win) {
        Send-GameKey BACKSPACE -Repeat 40 -GapMs 10
        Start-Sleep -Milliseconds 100
        return $true
    }
    return $false
}

if (-not (Ensure-ConsoleOpen $w)) {
    Write-Host "控制台打不开（像素探针连续两次判否）—— 中止，未发送任何指令。" -ForegroundColor Red
    Write-Host "提示：手动按 ~ 打开控制台后再用 -NoProbe 重试。" -ForegroundColor Yellow
    exit 4
}

# ---------------------------------------------------------------- 逐条执行
foreach ($c in $list) {
    # 每一条之前都重新确认：restart / stage 这类命令会让控制台自己关上
    if (-not (Ensure-ConsoleOpen $w)) {
        Write-Host ("控制台在执行「{0}」之前关掉了 —— 中止，后续指令未发送。" -f $c) -ForegroundColor Red
        exit 4
    }
    Write-Host ("  > " + $c) -ForegroundColor Cyan
    Send-GameText $c
    Start-Sleep -Milliseconds 120
    Send-GameKey ENTER
    Start-Sleep -Milliseconds 150
    Send-GameKey ENTER          # 自动补全要吃一次 ENTER
    Start-Sleep -Milliseconds $Settle
}

if (-not $KeepOpen) {
    Send-GameKey ESCAPE
    Start-Sleep -Milliseconds 250
}

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
