# =============================================================================
# archive.ps1 —— 把游戏里的存档合并进"永久离线档案"
#
# 背景：游戏内只保留最近 10 局（config.maxRuns），更早的会被淘汰。
#       这个脚本把每次看到的局都合并进 _archive\all.dat，**去重、只增不减**。
#
# 关键在于：**每次生成册子时会自动跑一次**，所以只要你看册子，就不会丢数据。
# （游戏里没法自己写文件——io 被沙箱移除，只能由外部脚本代劳）
#
# 用法：pwsh tools\archive.ps1
# =============================================================================
param(
    [string]$DataDir = "",
    [string]$ArchiveDir = ""
)

$ErrorActionPreference = "Stop"
$Game = "D:\LenovoSoftstore\Install\Steam\steamapps\common\The Binding of Isaac Rebirth"
if (-not $DataDir)    { $DataDir    = Join-Path $Game "data\highlight-review" }
$Root = Split-Path $PSScriptRoot -Parent
if (-not $ArchiveDir) { $ArchiveDir = Join-Path $Root "_archive" }
$Archive = Join-Path $ArchiveDir "all.dat"

function Read-Shared([string]$path) {
    $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose(); $fs.Dispose() }
}

# 把一份存档切成"局块"：每块 = 一个 R 行 + 其后的 F/M 行
function Split-Runs([string]$blob) {
    $runs = @()
    $cur = $null
    foreach ($line in ($blob -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -eq "MRV2") { continue }
        if ($line.StartsWith("R|")) {
            if ($cur) { $runs += ,$cur }
            $cur = [System.Collections.Generic.List[string]]::new()
            $cur.Add($line)
        } elseif ($cur) {
            $cur.Add($line)
        }
    }
    if ($cur) { $runs += ,$cur }
    return $runs
}

function Run-Key($lines) {
    # 用稳定身份当键：seq + id + t0。
    # 不能直接用 R 行 —— 同一局从"未完成"变"已通关"时 res/final 会变，R 行就不同了。
    $r = $lines[0]
    $seq = ([regex]::Match($r, '(?:^|/)seq=(\d+)')).Groups[1].Value
    $id  = ([regex]::Match($r, '(?:^|/)id=([^/]+)')).Groups[1].Value
    $t0  = ([regex]::Match($r, '(?:^|/)t0=(\d+)')).Groups[1].Value
    return "$seq|$id|$t0"
}

function Run-Seq($lines) {
    $m = [regex]::Match($lines[0], '(?:^|/)seq=(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

# ---------------------------------------------------------------- 现有档案
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir | Out-Null }

$known = @{}
$allRuns = @()
if (Test-Path $Archive) {
    foreach ($r in (Split-Runs (Read-Shared $Archive))) {
        $k = Run-Key $r
        if (-not $known.ContainsKey($k)) { $known[$k] = $allRuns.Count; $allRuns += ,$r }
        elseif ($r.Count -gt $allRuns[$known[$k]].Count) { $allRuns[$known[$k]] = $r }
    }
}

$before = $allRuns.Count
$added  = 0

# ---------------------------------------------------------------- 合并游戏存档
$files = Get-ChildItem $DataDir -Filter "save*.dat" -ErrorAction SilentlyContinue
foreach ($f in $files) {
    $blob = Read-Shared $f.FullName
    foreach ($r in (Split-Runs $blob)) {
        $k = Run-Key $r
        if (-not $known.ContainsKey($k)) {
            $known[$k] = $allRuns.Count
            $allRuns += ,$r
            $added++
        } elseif ($r.Count -gt $allRuns[$known[$k]].Count) {
            # 同一局后来存得更完整（比如续接后打完），替换掉旧的那份
            $allRuns[$known[$k]] = $r
            $added++
        }
    }
}

# ---------------------------------------------------------------- 排序 + 写回
$allRuns = $allRuns | Sort-Object { Run-Seq $_ }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append("MRV2`n")
foreach ($r in $allRuns) { foreach ($l in $r) { [void]$sb.Append($l + "`n") } }
[System.IO.File]::WriteAllText($Archive, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$size = (Get-Item $Archive).Length
Write-Host ("档案: {0}" -f $Archive) -ForegroundColor Green
Write-Host ("  已有 {0} 局 → 现在 {1} 局（本次新增 {2} 局）   {3:N0} 字节" -f `
    $before, $allRuns.Count, $added, $size)
Write-Host ("  扫描的存档: " + (($files | ForEach-Object { $_.Name }) -join ", "))
