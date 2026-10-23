# =============================================================================
# import-rating.ps1 —— 把旧数据里的道具评级导入评级 mod
#
# 背景：v0.3 时代评级存在「回顾 mod」的 saveN.dat 里（Q= 行）。
# 拆分成两个 mod 后，评级数据搬到了 data\highlight-rating\，旧数据不会自动跟过去。
# 本脚本把它们合并进去。
#
# 用法（**必须先关闭游戏**，否则游戏退出时会把文件覆盖回去）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-rating.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-rating.ps1
#
# 合并规则：同一道具 id，**导入的优先**（那是你手设的）；其余保留现有条目。
# 每次运行前都会备份到 _backup\import-rating-<时间戳>\。
# =============================================================================
param([switch]$DryRun, [switch]$SkipProcessCheck)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

. "$PSScriptRoot\_paths.ps1"
$Root    = Split-Path $PSScriptRoot -Parent
$DataDir = Join-Path $IsaacDir "data"
$Rating  = Join-Path $DataDir "highlight-rating"
$Review  = Join-Path $DataDir "highlight-review"
$BackupRoot = Join-Path $Root "_backup"

if (-not $SkipProcessCheck -and (Get-Process isaac-ng -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 游戏正在运行。请先完全关闭游戏再跑本脚本。" -ForegroundColor Red
    exit 2
}

# ── 解析一行 Q= 里的条目 ────────────────────────────────────────────────────
function Get-Entries([string]$line) {
    $out = @{}
    if (-not $line) { return $out }
    foreach ($m in [regex]::Matches($line, '"(\d+)"\s*:\s*\{([^}]*)\}')) {
        $id = $m.Groups[1].Value
        $body = $m.Groups[2].Value
        $q = [regex]::Match($body, '"q"\s*:\s*(-?[\d.]+)')
        $w = [regex]::Match($body, '"w"\s*:\s*(-?[\d.]+)')
        $on = [regex]::Match($body, '"on"\s*:\s*(true|false)')
        $e = [ordered]@{ q = ($(if ($q.Success) { [double]$q.Groups[1].Value } else { 0 })) }
        $e.w = ($(if ($w.Success) { [double]$w.Groups[1].Value } else { 1 }))
        if ($on.Success) { $e.on = ($on.Groups[1].Value -eq "true") }
        $out[$id] = $e
    }
    return $out
}

function Format-Num([double]$v) {
    $s = $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    return $s
}

function Build-QLine([hashtable]$entries) {
    $ids = $entries.Keys | Sort-Object { [int]$_ }
    $parts = @()
    foreach ($id in $ids) {
        $e = $entries[$id]
        $fields = @()
        $fields += '"q":' + (Format-Num $e.q)
        $fields += '"w":' + (Format-Num $e.w)
        if ($e.Contains("on")) { $fields += '"on":' + $(if ($e.on) { "true" } else { "false" }) }
        $parts += '"' + $id + '":{' + ($fields -join ",") + '}'
    }
    return 'Q={"v":1,"e":{' + ($parts -join ",") + '}}'
}

# ── 逐个存档槽处理 ─────────────────────────────────────────────────────────
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $BackupRoot ("import-rating-" + $stamp)

foreach ($slot in @("save1", "save2", "save3")) {
    $ratingFile = Join-Path $Rating "$slot.dat"
    $reviewFile = Join-Path $Review  "$slot.dat"

    # 导入源：① 回顾 mod 存档里的旧 Q 行  ② _backup 里被清掉的那份
    $sources = @()
    if (Test-Path $reviewFile) {
        $old = [System.IO.File]::ReadAllLines($reviewFile, [System.Text.Encoding]::UTF8) | Where-Object { $_ -like "Q=*" } | Select-Object -First 1
        if ($old) { $sources += @{ Name = "review/$slot"; Line = $old } }
    }
    $bkFiles = Get-ChildItem $BackupRoot -Filter "$slot-cleared-*.dat" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($bkFiles) {
        $old2 = [System.IO.File]::ReadAllLines($bkFiles[0].FullName, [System.Text.Encoding]::UTF8) | Where-Object { $_ -like "Q=*" } | Select-Object -First 1
        if ($old2) { $sources += @{ Name = ($bkFiles[0].Name); Line = $old2 } }
    }

    if ($sources.Count -eq 0) { Write-Host ("  {0}: 没有可导入的旧数据" -f $slot); continue }

    # 现有条目
    $cur = @{}
    if (Test-Path $ratingFile) {
        $curLine = [System.IO.File]::ReadAllLines($ratingFile, [System.Text.Encoding]::UTF8) | Where-Object { $_ -like "Q=*" } | Select-Object -First 1
        $cur = Get-Entries $curLine
    }
    $beforeIds = $cur.Keys | Sort-Object

    # 合并（导入的覆盖同 id）
    foreach ($s in $sources) {
        foreach ($k in (Get-Entries $s.Line).Keys) {
            $cur[$k] = (Get-Entries $s.Line)[$k]
        }
    }

    $newLine = Build-QLine $cur
    Write-Host ("  {0}: 现有 {1} 条 → 合并后 {2} 条" -f $slot, $beforeIds.Count, $cur.Count)
    Write-Host ("      来源: {0}" -f (($sources | ForEach-Object { $_.Name }) -join ", "))
    Write-Host ("      {0}" -f $newLine)

    if ($DryRun) { continue }

    # 备份 + 写入
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    if (Test-Path $ratingFile) { Copy-Item $ratingFile (Join-Path $backupDir ("rating-" + $slot + ".dat")) -Force }

    $lines = @()
    if (Test-Path $ratingFile) {
        $lines = [System.IO.File]::ReadAllLines($ratingFile, [System.Text.Encoding]::UTF8) | Where-Object { $_ -notlike "Q=*" }
    } else {
        $lines = @("IWE1")
    }
    $lines = @($lines) + $newLine
    [System.IO.File]::WriteAllLines($ratingFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("      ✔ 已写入 {0}" -f $ratingFile)
}

if ($DryRun) { Write-Host "`n（-DryRun：只演示，没有写文件）" }
elseif (Test-Path $backupDir) { Write-Host ("`n备份在 {0}" -f $backupDir) }
