# =============================================================================
# items-json.ps1 —— 生成道具名表（合并两个来源）
#
# 来源 1：mod 运行时 dump（日志里的 [DUMP] NAME 行）
#   id / quality / gfx / 原始 Name / 本地化名
#   · mod 道具的原始 Name 是明文（"Bread with Cheese"）→ 直接可用
#   · 原版道具的原始 Name 是本地化 key（"#THE_D6_NAME"）→ 需要来源 2
# 来源 2：EID 的中文名表
#   mods\external item descriptions_*\descriptions\names\zh_cn.lua
#   里面是 id → 中文名（只覆盖约 700 个原版道具）
#
# 输出：_logs\items.lua（离线册子直接 loadfile）+ _logs\items.json
# 用法：启动游戏进一局 → 退出 → pwsh tools\items-json.ps1
# =============================================================================
param(
    [string]$Log = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
if (-not $Log)    { $Log = Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance\log.txt" }
if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot "_logs" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

function Read-Shared([string]$path) {
    $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose(); $fs.Dispose() }
}

$items = @{}   # id -> pscustomobject

# ---------------------------------------------------------------- 来源 2：EID
$eidNames = @{}
$eidDir = Get-ChildItem (Join-Path $IsaacDir "mods") -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match "external item descriptions" } | Select-Object -First 1
if ($eidDir) {
    $eidFile = Join-Path $eidDir.FullName "descriptions\names\zh_cn.lua"
    if (Test-Path $eidFile) {
        $et = [System.IO.File]::ReadAllText($eidFile, [System.Text.Encoding]::UTF8)
        foreach ($m in [regex]::Matches($et, '\[\s*C_ID\s*\.\.\s*(\d+)\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"')) {
            $n = $m.Groups[2].Value.Replace('\"', '"')
            if ($n -ne "") { $eidNames[[int]$m.Groups[1].Value] = $n }
        }
    }
}
Write-Host ("EID 中文名: {0} 个" -f $eidNames.Count) -ForegroundColor DarkGray

# ---------------------------------------------------------------- 来源 1：dump
if (-not (Test-Path $Log)) { throw "找不到日志: $Log" }
Write-Host "读日志..." -ForegroundColor DarkGray
$text = Read-Shared $Log

$dumpCount = 0
# 兼容 3/4/5 列（旧版本只有 4 列，且名字为空）
#   5 列：id, q, gfx, 原始Name, 本地化名
#   4 列：id, q, gfx, 名字
foreach ($line in ($text -split "`r?`n")) {
    $i = $line.IndexOf("[DUMP] NAME")
    if ($i -lt 0) { continue }
    $rest = $line.Substring($i + 11).TrimStart([char]9)
    $parts = $rest -split "`t"
    if ($parts.Count -lt 3) { continue }
    $id = 0
    if (-not [int]::TryParse($parts[0], [ref]$id)) { continue }
    $q = -1
    [void][int]::TryParse($parts[1], [ref]$q)
    $gfx = $parts[2]
    $raw = if ($parts.Count -ge 5) { $parts[3] } elseif ($parts.Count -eq 4) { $parts[3] } else { "" }
    $loc = if ($parts.Count -ge 5) { $parts[4] } else { "" }
    $items[$id] = [pscustomobject]@{
        q   = $q
        gfx = $gfx.Trim()
        raw = $raw.Trim()
        loc = $loc.Trim()
    }
    $dumpCount++
}
Write-Host ("dump 名字行: {0} 行（去重后 {1} 个道具）" -f $dumpCount, $items.Count) -ForegroundColor DarkGray

if ($items.Count -eq 0) {
    Write-Host ""
    Write-Host "日志里没有 [DUMP] NAME 行。" -ForegroundColor Yellow
    Write-Host "  1) 确认 mod 已部署（工具链刚才部署过）"
    Write-Host "  2) 启动游戏、进一局（第一次进房会导出）"
    Write-Host "  3) 退出后重跑本脚本"
    exit 2
}

# ---------------------------------------------------------------- 合并优先级
# 1) 本地化名（GetLocalizedString 成功时）
# 2) mod 明文名（原始 Name 不以 # 开头）
# 3) EID 中文名（原版 #KEY 的兜底）
$final = @{}
foreach ($id in $items.Keys) {
    $it = $items[$id]
    $name = ""
    $src = ""
    if ($it.loc -ne "") { $name = $it.loc; $src = "loc" }
    elseif ($it.raw -ne "" -and -not $it.raw.StartsWith("#")) { $name = $it.raw; $src = "mod-review" }
    elseif ($eidNames.ContainsKey($id)) { $name = $eidNames[$id]; $src = "eid" }
    if ($name -ne "") { $final[$id] = [pscustomobject]@{ n = $name; q = $it.q; gfx = $it.gfx; src = $src } }
}

$srcCount = @{ loc = 0; mod = 0; eid = 0 }
foreach ($v in $final.Values) { if ($srcCount.ContainsKey($v.src)) { $srcCount[$v.src]++ } }

# ---------------------------------------------------------------- 输出
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("-- 自动生成，别手改。来源：tools\items-json.ps1")
[void]$sb.AppendLine("return {")
foreach ($id in ($final.Keys | Sort-Object)) {
    $v = $final[$id]
    $n = $v.n.Replace('\', '\\').Replace('"', '\"')
    [void]$sb.AppendLine(('  [{0}]={{q={1},n="{2}"}},' -f $id, $v.q, $n))
}
[void]$sb.AppendLine("}")
$luaPath = Join-Path $OutDir "items.lua"
[System.IO.File]::WriteAllText($luaPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$jsonObj = [ordered]@{}
foreach ($id in ($final.Keys | Sort-Object)) {
    $jsonObj[[string]$id] = [ordered]@{ name = $final[$id].n; quality = $final[$id].q }
}
$jsonPath = Join-Path $OutDir "items.json"
$jsonObj | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host ""
Write-Host ("名字表: {0} 个道具有名子" -f $final.Count) -ForegroundColor Green
Write-Host ("  仅本地化名 {0} · mod 明文名 {1} · EID 中文名 {2}" -f $srcCount.loc, $srcCount.mod, $srcCount.eid) -ForegroundColor Green
Write-Host ("  {0}" -f $luaPath) -ForegroundColor Green
Write-Host ("  {0}" -f $jsonPath) -ForegroundColor Green
Write-Host ""
Write-Host "抽样（没名字的，用来找漏）：" -ForegroundColor Cyan
$missing = @($items.Keys | Where-Object { -not $final.ContainsKey($_) } | Sort-Object)[0..7]
foreach ($id in $missing) { Write-Host ("  {0,-5} raw={1}" -f $id, $items[$id].raw) }
