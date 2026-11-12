# =============================================================================
# save-watch.ps1 -- 常驻的“存档定时备份”窗口（可见，不是后台任务）
#
#   tools\save-watch.cmd                 正常启动（桌面/开机自启用这个）
#   powershell -File tools\save-watch.ps1 -Once    只跑一轮，给自己看
#
# 来源和间隔都在 tools\watch-sources.json 里；加一份新来源 = 加一条 JSON。
# 窗口关掉 = 停止备份（这就是“能被看到”的代价，也是它的好处）。
# =============================================================================
param(
    [string]$Config = "",
    [string]$Root = "",
    [switch]$Once
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ProjectRoot = Split-Path $PSScriptRoot -Parent
if (-not $Config) { $Config = Join-Path $PSScriptRoot "watch-sources.json" }
if (-not $Root) { $Root = Join-Path $ProjectRoot "_logs\save-backup" }

. (Join-Path $PSScriptRoot "save-lib.ps1")

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }
function HHmmss($t) { return $t.ToString("HH:mm:ss") }

$script:TitleBase = "以撒存档备份"

# ---------------------------------------------------------------- 头
$isaac = Get-IsaacDirSafe
Say "" 
Say "==============================================================" Cyan
Say "  以撒存档定时备份" White
Say "==============================================================" Cyan
if (-not $isaac) {
    Say "  找不到游戏目录：设环境变量 ISAAC_DIR，或改 tools\_paths.ps1" Red
    Say "  窗口会每 60 秒重试一次。" Yellow
}
Say ("  仓库: {0}" -f $ProjectRoot) DarkGray
Say ("  配置: {0}" -f $Config) DarkGray
Say ("  快照: {0}" -f $Root) DarkGray

$sources = @()
try {
    $sources = @(Get-Sources $Config $isaac)
} catch {
    Say ("  配置读不出来：" + $_.Exception.Message) Red
    Say "  先用内置的两个来源继续跑。" Yellow
    $sources = @(Get-DefaultSources)
}
Say ("  来源 {0} 个：" -f $sources.Count) White
foreach ($s in $sources) {
    Say ("    - {0,-18} 每 {1,3} 分钟  {2}" -f $s.name, $s.everyMinutes, $s.path) Gray
}
Say "  Ctrl+C 结束（关窗口也会结束）" DarkGray
Say "==============================================================" Cyan
Say ""

if ($Once) {
    $bad = 0
    foreach ($s in $sources) {
        $r = Invoke-Source $s $Root
        foreach ($e in $r.Events) {
            $c = if ($e.Kind -eq "ok") { "Green" } elseif ($e.Kind -eq "bad") { "Red" } elseif ($e.Kind -eq "warn") { "Yellow" } else { "DarkGray" }
            Say ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $e.Text) $c
        }
        if ($r.Events.Count -eq 0) { Say ("[{0}] {1} 未变（{2} 个文件）" -f (Get-Date -Format "HH:mm:ss"), $s.name, $r.Total) DarkGray }
        Add-BackupLog $Root ("[{0}] 新增 {1} 未变 {2} 失败 {3}" -f $s.name, $r.Saved, $r.Same, $r.Bad)
        if ($r.Bad -gt 0) { $bad++ }
    }
    exit $bad
}

# ---------------------------------------------------------------- 单实例
# 桌面/开机自启可能同时拉起两个窗口；后开的那个看到锁里有活进程就直接退出。
if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }
$lockFile = Join-Path $Root ".watcher.lock"
if (Test-Path -LiteralPath $lockFile) {
    $busy = $null
    try {
        $info = Get-Content -LiteralPath $lockFile -Raw | ConvertFrom-Json
        $busy = Get-Process -Id ([int]$info.pid) -ErrorAction SilentlyContinue
        if ($busy -and $busy.ProcessName -notmatch "powershell") { $busy = $null }   # PID 被别的程序复用了
    } catch { }
    if ($busy) {
        Say ("另一个备份窗口正在运行（PID {0}），本窗口退出。" -f $busy.Id) Yellow
        Start-Sleep -Seconds 3
        exit 0
    }
}
Set-Content -LiteralPath $lockFile -Value (ConvertTo-Json @{ pid = $PID; started = (Get-Date).ToString("s") }) -Encoding UTF8
$script:LockFile = $lockFile

# ---------------------------------------------------------------- 常驻循环
$script:StartedAt = Get-Date
$next = @{}
foreach ($s in $sources) { $next[$s.name] = $script:StartedAt }
$lastBeat = Get-Date

try {
    while ($true) {
        $now = Get-Date

        if (-not $isaac) {
            $isaac = Get-IsaacDirSafe
            if ($isaac) {
                Say ("[{0}] 找到游戏目录：{1}" -f (HHmmss $now), $isaac) Green
                try { $sources = @(Get-Sources $Config $isaac); foreach ($s in $sources) { $next[$s.name] = $now } } catch { }
            } else {
                if (($now - $lastBeat).TotalSeconds -ge 60) { Say ("[{0}] 还在等游戏目录…" -f (HHmmss $now)) DarkYellow; $lastBeat = $now }
                Start-Sleep -Seconds 2
                continue
            }
        }

        foreach ($s in $sources) {
            if ($now -lt $next[$s.name]) { continue }

            $r = Invoke-Source $s $Root
            foreach ($e in $r.Events) {
                $c = if ($e.Kind -eq "ok") { "Green" } elseif ($e.Kind -eq "bad") { "Red" } elseif ($e.Kind -eq "warn") { "Yellow" } else { "DarkGray" }
                Say ("[{0}] {1}" -f (HHmmss $now), $e.Text) $c
            }
            if ($r.Events.Count -eq 0) {
                Say ("[{0}] {1,-18} 未变（{2} 个文件）" -f (HHmmss $now), $s.name, $r.Total) DarkGray
            } else {
                Say ("[{0}] {1,-18} 本轮：新增 {2}，未变 {3}，失败 {4}" -f (HHmmss $now), $s.name, $r.Saved, $r.Same, $r.Bad) Gray
            }
            Add-BackupLog $Root ("[{0}] 新增 {1} 未变 {2} 失败 {3}" -f $s.name, $r.Saved, $r.Same, $r.Bad)

            $mins = [Math]::Max(1, [int]$s.everyMinutes)
            $next[$s.name] = $now.AddMinutes($mins)
        }

        # 标题栏：显示下一次的时间
        $soonest = ($next.Values | Sort-Object | Select-Object -First 1)
        try { $Host.UI.RawUI.WindowTitle = ("{0} · 下次 {1}" -f $script:TitleBase, (HHmmss $soonest)) } catch { }

        # 每 10 分钟一行心跳，证明它还活着
        if (($now - $lastBeat).TotalMinutes -ge 10) {
            $runFor = [int](($now - $script:StartedAt).TotalMinutes)
            Say ("—— 运行中 {0} 分钟 · 下次 {1} ——" -f $runFor, (HHmmss $soonest)) DarkCyan
            $lastBeat = $now
        }

        Start-Sleep -Seconds 1
    }
} finally {
    if ($script:LockFile) { Remove-Item -LiteralPath $script:LockFile -Force -ErrorAction SilentlyContinue }
    try { $Host.UI.RawUI.WindowTitle = "$($script:TitleBase) · 已停止" } catch { }
    Say ""
    Say "已停止定时备份。" Yellow
}
