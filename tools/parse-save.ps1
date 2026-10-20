# =============================================================================
# parse-save.ps1 —— v2 记录流 → 人能看懂的 JSON
#
# v2 的字段是 key=value，所以**本脚本不需要知道 schema**：
# 每个 k=v 原样搬进 JSON，数字自动转数字，带 + 的纯数字串转数组。
# 以后游戏里加字段，这里不用改。
#
# 用法：
#   pwsh tools\parse-save.ps1               # 全部槽，写 JSON + 控制台摘要
#   pwsh tools\parse-save.ps1 -Slot 1
#   pwsh tools\parse-save.ps1 -Summary      # 只打摘要，不写文件
# =============================================================================
param(
    [string]$Slot = "all",
    [switch]$Summary,
    [string]$OutDir = "",
    [string]$DataDir = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
$Game = $IsaacDir
if (-not $DataDir) { $DataDir = Join-Path $Game "data\highlight-review" }
$Root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $Root "_logs" }
$Inv = [System.Globalization.CultureInfo]::InvariantCulture

function Convert-Value([string]$s) {
    if ($null -eq $s) { return $null }
    if ($s.IndexOf("+") -ge 0) {
        $parts = $s.Split("+")
        $nums = @()
        $allNum = $true
        foreach ($p in $parts) {
            $n = 0.0
            if ([double]::TryParse($p, [System.Globalization.NumberStyles]::Float, $Inv, [ref]$n)) {
                $nums += [long][math]::Round($n)
            } else { $allNum = $false; break }
        }
        if ($allNum) { return ,$nums }
        return $s
    }
    $v = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, $Inv, [ref]$v)) {
        if ($v -eq [math]::Floor($v)) { return [long]$v }
        return [math]::Round($v, 2)
    }
    return $s
}

function Parse-Record([string]$line) {
    $scope = $line.Substring(0, 1)
    $rest = if ($line.Length -gt 2) { $line.Substring(2) } else { "" }
    $obj = [ordered]@{ scope = $scope }
    foreach ($pair in $rest.Split("/")) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $i = $pair.IndexOf("=")
        if ($i -lt 0) { continue }
        $obj[$pair.Substring(0, $i)] = Convert-Value $pair.Substring($i + 1)
    }
    return $obj
}

function Parse-Blob([string]$path) {
    $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
    $runs = @(); $warnings = @(); $first = $true
    $cur = $null
    try {
        while ($null -ne ($line = $sr.ReadLine())) {
            if ($first) {
                $first = $false
                if ($line.Trim() -ne "MRV2") { $warnings += "魔数不符: $line" }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $rec = Parse-Record $line
            if ($rec.scope -eq "R") {
                $resTxt = switch ([string]$rec.res) { "0" { "died" } "1" { "won" } default { "unfinished" } }
                $cur = [pscustomobject]@{
                    seq = $rec.seq; id = $rec.id; seed = $rec.seed; char = $rec.char
                    base = $rec.base; final = $rec.final; maxFloor = $rec.max
                    result = $resTxt; t0 = $rec.t0; hlCount = $rec.hl
                    floors = [System.Collections.ArrayList]@()
                    rooms  = [System.Collections.ArrayList]@()
                }
                $runs += $cur
            }
            elseif ($rec.scope -eq "F") {
                if ($cur) { [void]$cur.floors.Add([pscustomobject]$rec) } else { $warnings += "游离 F 行" }
            }
            elseif ($rec.scope -eq "M") {
                if (-not $cur) { $warnings += "游离 M 行"; continue }
                $delta = 0; $pct = 0; $sec = 0
                if ($null -ne $rec.po -and $null -ne $rec.p) {
                    $delta = [math]::Round($rec.po - $rec.p, 2)
                    if ($rec.p -gt 0) { $pct = [math]::Round($delta / $rec.p * 100, 1) }
                }
                if ($null -ne $rec.ms) { $sec = [math]::Round($rec.ms / 1000.0, 1) }
                $rec["delta"] = $delta
                $rec["deltaPct"] = $pct
                $rec["seconds"] = $sec
                [void]$cur.rooms.Add([pscustomobject]$rec)
            }
            elseif ($rec.scope -eq "Q" -or $rec.scope -eq "C") { }   # 评级/设置行，不参与房间解析
            else { $warnings += "未知作用域: $($rec.scope)" }
        }
    } finally { $sr.Dispose(); $fs.Dispose() }

    [pscustomobject]@{
        source   = $path
        runs     = $runs
        warnings = $warnings
        summary  = [pscustomobject]@{
            runCount  = $runs.Count
            roomCount = ($runs | ForEach-Object { $_.rooms.Count } | Measure-Object -Sum).Sum
            bytes     = (Get-Item $path).Length
        }
    }
}

# ---------------------------------------------------------------- 主流程

if (-not (Test-Path $DataDir)) { Write-Host "还没有存档目录: $DataDir" -ForegroundColor Yellow; exit 2 }
$files = if ($Slot -eq "all") { Get-ChildItem $DataDir -Filter "save*.dat" | Sort-Object Name }
         else { Get-ChildItem $DataDir -Filter "save$Slot.dat" }
if (-not $files) { Write-Host "没找到匹配的存档" -ForegroundColor Yellow; exit 2 }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

foreach ($f in $files) {
    $parsed = Parse-Blob $f.FullName
    Write-Host ""
    Write-Host ("=== {0}  ({1:N0} 字节 / {2} 局 / {3} 个房间) ===" -f `
        $f.Name, $parsed.summary.bytes, $parsed.summary.runCount, $parsed.summary.roomCount) -ForegroundColor Cyan
    if ($parsed.warnings.Count -gt 0) {
        Write-Host ("  警告 {0} 条：{1}" -f $parsed.warnings.Count, ($parsed.warnings -join "; ")) -ForegroundColor Yellow
    }

    foreach ($r in $parsed.runs) {
        Write-Host ("  #{0} {1,-12} {2,-10} {3}层  {4} -> {5}  {6} 房" -f `
            $r.seq, $r.id, $r.result, $r.maxFloor, $r.base, $r.final, $r.rooms.Count)
        foreach ($room in $r.rooms) {
            $mark = if ($room.delta -gt 0.01) { "+" } elseif ($room.delta -lt -0.01) { "-" } else { " " }
            $it = if ($room.it) { "  道具:" + ($room.it -join ",") } else { "" }
            $hpTxt = "红{0}->{1} 魂{2}->{3}" -f $room.hp, $room.hpo, $room.hs, $room.hso
            if ($room.tri -or $room.tro) { $hpTxt += ("  饰品:" + (@($room.tri) -join ",") + "→" + (@($room.tro) -join ",")) }
            Write-Host ("      F{0}-{1,2} 型{2,-2} {3,6:0.00}{4}{5,-6:0.00}  {6,6:0.0}s  伤{7}  {8}{9}" -f `
                $room.f, $room.i, $room.t, $room.p, $mark, $room.po, $room.seconds, $room.dmg, $hpTxt, $it) -ForegroundColor DarkGray
        }
    }

    if (-not $Summary) {
        $out = Join-Path $OutDir ("{0}-{1}.json" -f $f.BaseName, $stamp)
        $parsed | ConvertTo-Json -Depth 20 | Set-Content -Path $out -Encoding UTF8
        Write-Host ("  → JSON: {0}" -f $out) -ForegroundColor Green
    }
}
