# =============================================================================
# strip-log.ps1 —— 生成"去噪日志副本"（原文件只读，绝不修改）
#
# 为什么：某些 mod 会把同一行刷几十万遍（当前 log.txt 里 96% 是
# PushRenderTarget assert），直接读会淹没真正的信息。
#
# 设计原则：
#   1. 原文件只读 —— 游戏正在写，动它会丢现场
#   2. 不静默丢弃 —— 头部记账：删了多少行、按什么模式删的
#   3. 连续重复行折叠成一行 + 次数（事实保留，不是消失）
#
# 用法：
#   pwsh tools\strip-log.ps1                                  # 当前 log.txt
#   pwsh tools\strip-log.ps1 -Session 3                        # 倒数第 3 次启动
#   pwsh tools\strip-log.ps1 -AddDrop "no animation named"
#   pwsh tools\strip-log.ps1 -KeepOnly HIGHLIGHT,attempt,NPC   # 只留命中行
# =============================================================================
param(
    [string]$Log = "",
    [int]$Session = 1,
    [string[]]$Drop = @("PushRenderTarget: stack overflow"),
    [string[]]$AddDrop = @(),
    [string[]]$KeepOnly = @(),
    [int]$After = 2,            # KeepOnly 命中行之后再多留几行（看堆栈用）
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$Docs = Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance"
$Root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $Root "_logs" }

$Drop = @($Drop) + @($AddDrop) | Where-Object { $_ }

# ---------------------------------------------------------------- 选源文件
if (-not $Log) {
    if ($Session -le 1) {
        $Log = Join-Path $Docs "log.txt"
    } else {
        $sessions = Get-ChildItem $Docs -Filter "isaacv*.txt" | Sort-Object LastWriteTime -Descending
        if ($sessions.Count -lt $Session) { throw "找不到第 $Session 次会话日志" }
        $Log = $sessions[$Session - 1].FullName
    }
}
if (-not (Test-Path $Log)) { throw "找不到日志: $Log" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$OutPath = Join-Path $OutDir ("clean-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

# ---------------------------------------------------------------- 单遍过滤
$out         = New-Object System.Collections.Generic.List[string]
$dropHits    = @{}
$totalLines  = 0
$dropped     = 0
$collapsed   = 0
$prev        = $null
$prevRepeat  = 1
$lookahead   = 0
$keepMode    = ($KeepOnly.Count -gt 0)

# 用 FileShare.ReadWrite 打开：游戏正持有该文件，默认共享模式会抛 IOException
$fs = [System.IO.FileStream]::new($Log, [System.IO.FileMode]::Open,
                                  [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
try {
while ($null -ne ($line = $sr.ReadLine())) {
    $totalLines++

    if ($keepMode) {
        $hit = $false
        foreach ($k in $KeepOnly) { if ($line.IndexOf($k, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break } }
        if ($hit) { $lookahead = $After }
        if ($hit -or $lookahead -gt 0) {
            $out.Add($line)
            if (-not $hit) { $lookahead-- }
        }
        continue
    }

    $droppedHere = $false
    foreach ($p in $Drop) {
        if ($line.IndexOf($p, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            if ($dropHits.ContainsKey($p)) { $dropHits[$p] = $dropHits[$p] + 1 } else { $dropHits[$p] = 1 }
            $droppedHere = $true
            $dropped++
            break
        }
    }
    if ($droppedHere) { continue }

    if ($line -ceq $prev) { $prevRepeat++; continue }

    if ($prevRepeat -gt 1) {
        $out.Add(("  ... 上一行连续重复 {0:N0} 次（已折叠）" -f $prevRepeat))
        $collapsed += ($prevRepeat - 1)
    }
    $prevRepeat = 1
    $prev = $line
    $out.Add($line)
}
} finally { $sr.Dispose(); $fs.Dispose() }
if ($prevRepeat -gt 1) {
    $out.Add(("  ... 上一行连续重复 {0:N0} 次（已折叠）" -f $prevRepeat))
    $collapsed += ($prevRepeat - 1)
}

# ---------------------------------------------------------------- 写文件（带头部）
$dropDesc = ($dropHits.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
if (-not $dropDesc) { $dropDesc = "（无）" }

$head = @(
    "======== 去噪日志副本 ========",
    ("源文件   : {0}" -f $Log),
    ("源大小   : {0:N0} 字节 / {1:N0} 行" -f (Get-Item $Log).Length, $totalLines),
    ("丢弃     : {0:N0} 行   模式：{1}" -f $dropped, $dropDesc),
    ("折叠     : {0:N0} 行连续重复（保留 1 行 + 次数）" -f $collapsed),
    ("保留     : {0:N0} 行" -f $out.Count),
    ("过滤模式 : {0}" -f $(if ($keepMode) { "只留含 [" + ($KeepOnly -join ", ") + "] 的行" } else { "去噪" })),
    ("说明     : 原文件未被修改，本副本仅供阅读排查。"),
    "==============================",
    ""
)

[System.IO.File]::WriteAllLines($OutPath, ($head + $out), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ""
Write-Host ("输出: {0}" -f $OutPath) -ForegroundColor Green
Write-Host ("  {0:N0} 行  ->  {1:N0} 行" -f $totalLines, ($out.Count + $head.Count))
if ($dropped -gt 0) {
    Write-Host ("  丢弃 {0:N0} 行：" -f $dropped) -ForegroundColor Yellow
    foreach ($k in $dropHits.Keys) { Write-Host ("    {0}  : {1:N0}" -f $k, $dropHits[$k]) -ForegroundColor Yellow }
}
if ($collapsed -gt 0) { Write-Host ("  折叠 {0:N0} 行连续重复" -f $collapsed) -ForegroundColor DarkGray }
