# =============================================================================
# verify.ps1 —— 进游戏自检：启动 → 进存档 → 按 F5 开册子 → 截图 + 查日志
#
# 目的：把"人肉进游戏点一遍"变成一条命令。跑完给你：
#   _logs\verify\<时间戳>\01-menu.png    主菜单
#                  02-run.png     进存档后的画面
#                  03-book.png    F5 之后的册子
#                  summary.txt    结论（加载 / 报错 / 引擎断言 / 关键日志）
#
# 用法：
#   powershell -File tools\verify.ps1 -Deploy -Launch -Enter -F5 -Close    # 全套
#   powershell -File tools\verify.ps1                                      # 只连上已在跑的游戏截图
#   powershell -File tools\verify.ps1 -Enter -F5                           # 游戏已开：进存档 + 开册子
#   powershell -File tools\verify.ps1 -Fresh -Launch                       # 清掉僵死进程再启动
#
# 退出码：0 = 正常；1 = 有 Lua 报错/引擎断言洪水；2 = 环境问题；3 = 键盘被抢（已中止）
# =============================================================================
param(
    [switch]$Deploy,          # 先把 mod/ 同步到游戏目录
    [switch]$Fresh,           # 进程在但没窗口（僵死）→ 结束它
    [switch]$Launch,          # 进程不在 → 启动游戏
    [switch]$ViaLauncher,     # 用 REPENTOGONLauncher 启动（实测会卡在联网检查，仅备用）
    [switch]$Enter,           # 进存档（自动连按，最多 4 次，直到日志出现进局信号）
    [switch]$F5,              # 按 F5（开/关册子）
    [switch]$Close,           # 结束后优雅关闭游戏（存档会被游戏写盘）
    [int]$WaitMenuSec = 180,
    [int]$WaitRunSec = 30,
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
. "$PSScriptRoot\_win.ps1"

$Docs    = Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance"
$LogFile = Join-Path $Docs "log.txt"
$Game    = $IsaacDir

if (-not $OutDir) {
    $OutDir = Join-Path $ProjectRoot ("_logs\verify\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$script:Offset   = 0
$script:AllNew   = New-Object System.Collections.ArrayList
$script:Problems = New-Object System.Collections.ArrayList

function Say([string]$msg) { Write-Host $msg }
function Head([string]$msg) { Write-Host ""; Write-Host "== $msg ==" -ForegroundColor Cyan }
function Ok([string]$msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Bad([string]$msg) {
    Write-Host "  ✗ $msg" -ForegroundColor Red
    [void]$script:Problems.Add($msg)
}

# ---------------------------------------------------------------- 日志增量
# 游戏重启时 log.txt 会被截断，所以发现文件变短就把 offset 归零。
function Read-NewLog {
    if (-not (Test-Path $LogFile)) { return @() }
    $len = (Get-Item $LogFile).Length
    if ($len -lt $script:Offset) { $script:Offset = 0 }
    if ($len -eq $script:Offset) { return @() }
    $fs = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
    try {
        [void]$fs.Seek($script:Offset, 'Begin')
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd()
        $script:Offset = $fs.Position
    } finally { $fs.Dispose() }
    $lines = @($text -split "`r?`n" | Where-Object { $_ -ne "" })
    foreach ($l in $lines) { [void]$script:AllNew.Add($l) }
    return $lines
}

function Wait-Log {
    param([string]$Pattern, [int]$TimeoutSec, [switch]$Quiet)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $hits = @()
    while ((Get-Date) -lt $deadline) {
        foreach ($l in (Read-NewLog)) {
            if ($l -match $Pattern) { $hits += $l }
        }
        if ($hits.Count -gt 0) { return $hits }
        Start-Sleep -Milliseconds 700
    }
    return $hits
}

function Shot([string]$name) {
    $w = Get-GameWindow
    if (-not $w -or $w.Handle -eq [IntPtr]::Zero) { Warn "没有窗口，跳过截图 $name"; return $null }
    try {
        $p = Save-WindowShot $w (Join-Path $OutDir "$name.png") -NoFocus
        Say ("  [截图] " + $p)
        return $p
    } catch {
        Warn ("截图失败：" + $_.Exception.Message)
        return $null
    }
}

# 截图前先确认游戏真的画完了：
#   启动阶段窗口标题带 "LuaEngine Initialized"，加载完才变回正常标题。
function Wait-GameReady {
    param([int]$TimeoutSec = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $w = Get-GameWindow
        if ($w -and $w.Handle -ne [IntPtr]::Zero) {
            if ($w.Title -notmatch "Initialized|Updater|Launcher") {
                Start-Sleep -Milliseconds 1200
                return $true
            }
        }
        Start-Sleep -Milliseconds 700
    }
    return $false
}

function Press([string]$key) {
    $w = Get-GameWindow
    if (-not $w -or $w.Handle -eq [IntPtr]::Zero) { throw "没有窗口，没法按键" }
    $ok = Focus-Window $w
    if (-not $ok) {
        Start-Sleep -Milliseconds 300
        $ok = Focus-Window $w
    }
    if (-not $ok) {
        Bad "按键前窗口没拿到前台（按键会发到别的程序），已中止"
        exit 3
    }
    Send-GameKey $key
    Say ("  [按键] " + $key) -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 500
}

function Kill-GameProcess {
    $p = Get-Process isaac-ng -ErrorAction SilentlyContinue
    if (-not $p) { return }
    Say ("  结束进程 isaac-ng (PID {0})" -f $p.Id)
    $p.CloseMainWindow() | Out-Null
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline -and (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 400
    }
    $p = Get-Process isaac-ng -ErrorAction SilentlyContinue
    if ($p) { Stop-Process -Id $p.Id -Force; Say "  已强制结束" }
}

function Start-Game {
    $exe      = Join-Path $Game "isaac-ng.exe"
    $launcher = Join-Path $Game "REPENTOGONLauncher\REPENTOGONLauncher.exe"

    if ($ViaLauncher) {
        if (-not (Test-Path $launcher)) { Bad "找不到 REPENTOGONLauncher.exe"; exit 2 }
        Say "  启动 REPENTOGONLauncher ..."
        Start-Process -FilePath $launcher
        return
    }

    # 默认走 Steam：等价于点“开始游戏”，app id 由 Steam 注入，最接近手动启动
    if (Get-Process steam -ErrorAction SilentlyContinue) {
        Say "  通过 Steam 启动（steam://rungameid/250900）..."
        Start-Process "steam://rungameid/250900"
        return
    }

    if (Test-Path $exe) {
        Say "  直接启动 isaac-ng.exe（Steam 没开，用 SteamAppId 兜底）..."
        $env:SteamAppId = "250900"
        Start-Process -FilePath $exe
        return
    }

    Bad "找不到游戏可执行文件：$Game"
    exit 2
}

# =============================================================================
Head "0) 准备"
Say ("  输出目录：" + $OutDir)
if (Test-Path $LogFile) {
    $script:Offset = (Get-Item $LogFile).Length
    Say ("  日志起点：{0:N0} 字节（只看之后新增的行）" -f $script:Offset)
} else {
    Say "  还没有 log.txt（游戏还没启动过）"
}

if ($Deploy) {
    Head "1) 部署 mod"
    & (Join-Path $PSScriptRoot "deploy.ps1")
}

# ---------------------------------------------------------------- 进程/窗口
Head "2) 进程与窗口"
$proc = Get-Process isaac-ng -ErrorAction SilentlyContinue
$alreadyRunning = ($null -ne $proc)
$w = $null
if ($proc) {
    $w = Get-GameWindow
    if (-not $w -or $w.Handle -eq [IntPtr]::Zero) {
        Warn ("游戏进程在（PID {0}）但没有可见窗口 —— 通常是关游戏时卡住的僵尸进程" -f $proc.Id)
        if ($Fresh) {
            Kill-GameProcess
            $proc = $null
        } else {
            Warn "加 -Fresh 可以自动结束它再重启"
            exit 2
        }
    }
}

if ($proc -and $w) {
    Ok ("游戏窗口：0x{0:X}  {1}" -f [int64]$w.Handle, $w.Title)
} else {
    if (-not $Launch -and -not $Fresh) {
        Warn "游戏没在跑。加 -Launch（或 -Fresh）让我启动它"
        exit 2
    }
    Start-Game
    Say ("  等游戏窗口出现（最多 {0}s）..." -f $WaitMenuSec)
    $deadline = (Get-Date).AddSeconds($WaitMenuSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        $w = Get-GameWindow
        if ($w -and $w.Handle -ne [IntPtr]::Zero) { break }
        $w = $null
    }
    if (-not $w) { Bad "等不到游戏窗口"; exit 2 }
    Ok ("游戏窗口：0x{0:X}" -f [int64]$w.Handle)
}

# ---------------------------------------------------------------- 等 mod 加载
Head "3) 等 mod 加载 + 主菜单就绪"
if ($alreadyRunning -and (Select-String -Path $LogFile -Pattern "\[HIGHLIGHT\] loaded" -Quiet)) {
    # 复用在跑的实例：加载日志在本脚本启动之前就写完了，不能只等新增行
    $loaded = @("(already loaded)")
    Ok "mod 已在当前会话加载过（复用运行中的游戏）"
} else {
    $loaded = Wait-Log -Pattern "\[HIGHLIGHT\] loaded" -TimeoutSec $WaitMenuSec
}
if ($loaded.Count -eq 0) {
    Bad ("等不到 '[HIGHLIGHT] loaded'（{0}s）——mod 没加载，或日志路径不对" -f $WaitMenuSec)
    [void](Shot "00-timeout")
    exit 2
}
Ok "mod 已加载"
if (-not (Wait-GameReady $WaitMenuSec)) { Warn "窗口标题一直显示启动中；仍尝试截图" }
Start-Sleep -Seconds 1
[void](Shot "01-menu")

# ---------------------------------------------------------------- 进存档
if ($Enter) {
    Head "4) 进存档"
    # 路上可能有三层：标题画面 → 存档槽（1/2/3）→ 存档内菜单（新游戏/继续游戏）
    $presses = 0
    $entered = $false
    while ($presses -lt 4 -and -not $entered) {
        Press "ENTER"
        $presses++
        $hit = Wait-Log -Pattern "\[HIGHLIGHT\] (F\d|开局|检查点落盘|续接)" -TimeoutSec 10
        if ($hit.Count -gt 0) { $entered = $true; break }
        Start-Sleep -Seconds 1
    }
    if ($entered) {
        Ok ("进局成功（按了 {0} 次 Enter）" -f $presses)
        Start-Sleep -Seconds 2
        [void](Shot "02-run")
    } else {
        Warn ("按了 {0} 次 Enter 仍没看到进局日志 —— 可能没有可续的局" -f $presses)
        [void](Shot "02-run")
    }
}

# ---------------------------------------------------------------- F5
if ($F5) {
    Head "5) 按 F5（册子开关）"
    $before = $script:AllNew.Count
    Press "F5"
    Start-Sleep -Seconds 2
    [void](Shot "03-book")
    [void](Read-NewLog)

    $delta = @()
    if ($script:AllNew.Count -gt $before) {
        $delta = @($script:AllNew[$before..($script:AllNew.Count - 1)])
    }
    $reload = @($delta | Where-Object { $_ -match "Running Lua Script: .*highlight-review/main\.lua" })
    if ($reload.Count -gt 0) {
        Warn "F5 把 mod 重载了一遍（日志里重新跑了 main.lua）——册子可能没开，需要换键"
    }
    $uiLines = @($delta | Where-Object { $_ -match "\[HIGHLIGHT\] \[UI\]" })
    if ($uiLines.Count -gt 0) { Ok "册子有响应（[UI] 日志）" } else { Warn "没看到 [UI] 日志（册子可能没开，或没有可显示的对局）" }
}

# ---------------------------------------------------------------- 结论
Head "6) 结论"
$all = @($script:AllNew | Where-Object { $_ -notmatch "\[HIGHLIGHT\] \[DUMP\]" })
# 注意用 -cmatch：道具名里有 "Fatal Current"，-match 不分大小写会误判
$fatal  = @($all | Where-Object { $_ -cmatch "\[HIGHLIGHT\].*(FATAL|!!! )" })
# "attempt to ..." 只在**不是** mod 自己捕获并降级处理的日志时才算报错
$errs   = @($all | Where-Object {
        ($_ -match "\[HIGHLIGHT\] ERROR|Lua Error|stack traceback") -or
        (($_ -match "attempt to ") -and ($_ -notmatch "Lua Debug: \[HIGHLIGHT\]"))
    })
$asserts = @($all | Where-Object { $_ -match "\[ASSERT\]" })
$warns  = @($all | Where-Object { $_ -match "\[HIGHLIGHT\].*(不可用|失败|跳过|回退|警告)" })

if ($fatal.Count -gt 0) { $fatal | Select-Object -First 5 | ForEach-Object { Bad ("FATAL: " + $_) } }
if ($errs.Count -gt 0) { $errs | Select-Object -First 10 | ForEach-Object { Bad ("报错: " + $_) } }
if ($warns.Count -gt 0) { $warns | Select-Object -First 8 | ForEach-Object { Warn $_ } }

# 引擎断言：一类问题只报一条，附次数。
# 注意：本机这套 mod 里，断言洪水来自第三方 mod（reverie 的 Pair 日志之后开始），
# 所以这里只作为"提示"报出来，不让它影响退出码。
$assertFlood = $false
if ($asserts.Count -gt 0) {
    $groups = $asserts | Group-Object { ($_ -replace '^\[ASSERT\] - ', '') } | Sort-Object Count -Descending
    foreach ($g in ($groups | Select-Object -First 3)) {
        if ($g.Count -ge 50) {
            $assertFlood = $true
            Warn ("引擎断言洪水 x{0}：{1}（可能来自第三方 mod，看 summary 的开头位置）" -f $g.Count, $g.Name)
        } else {
            Warn ("引擎断言 x{0}：{1}" -f $g.Count, $g.Name)
        }
    }
}

if ($fatal.Count -eq 0 -and $errs.Count -eq 0 -and -not $assertFlood) { Ok "没有 Lua 报错，也没有断言洪水" }

$summary = @(
    "时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    "输出: " + $OutDir
    "mod 加载: " + ($loaded.Count -gt 0)
    "FATAL: " + $fatal.Count + "   Lua 报错: " + $errs.Count + "   引擎断言: " + $asserts.Count + "   警告: " + $warns.Count
    "日志新增: " + $all.Count + " 行"
    ""
    "---- [HIGHLIGHT] / 断言（最多 60 行）----"
) + @($all | Where-Object { ($_ -match "\[HIGHLIGHT\]|FATAL|Lua Error|\[ASSERT\]") -and ($_ -notmatch "\[DUMP\]") } | Select-Object -Last 60)

$summaryPath = Join-Path $OutDir "summary.txt"
$summary -join "`r`n" | Set-Content -Path $summaryPath -Encoding UTF8
Say ("  summary: " + $summaryPath)

if ($Close) {
    Head "7) 关闭游戏"
    Kill-GameProcess
    $shut = Wait-Log -Pattern "shut down successfully" -TimeoutSec 15
    if ($shut.Count -gt 0) { Ok "游戏已正常退出（存档已写盘）" } else { Warn "没看到 shutdown 日志" }
}

if ($fatal.Count -gt 0 -or $errs.Count -gt 0) { exit 1 }
exit 0
