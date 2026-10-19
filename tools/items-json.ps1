# =============================================================================
# items-json.ps1 —— 从日志里提取"道具名表"，生成两个文件：
#   _logs\items.lua   Lua 表（离线册子直接 loadfile，零解析）
#   _logs\items.json  JSON（给人看 / 给别的工具）
#
# 数据来源：mod 里 core/dump.lua 的 dump.itemNames()，日志里形如
#   [HIGHLIGHT] [DUMP] NAME\t<id>\t<quality>\t<gfx>\t<本地化名>
#
# 用法：pwsh tools\items-json.ps1
# =============================================================================
param(
    [string]$Log = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
if (-not $Log)    { $Log = Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance\log.txt" }
if (-not $OutDir) { $OutDir = Join-Path $Root "_logs" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
if (-not (Test-Path $Log)) { throw "找不到日志: $Log" }

function Read-Shared([string]$path) {
    $fs = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose(); $fs.Dispose() }
}

Write-Host "读日志..." -ForegroundColor DarkGray
$text = Read-Shared $Log

# 只保留最后一次出现的（重复启动会有多份）
$items = @{}
$count = 0
foreach ($m in [regex]::Matches($text, '(?m)^\[INFO\] - Lua Debug: \[HIGHLIGHT\] \[DUMP\] NAME\t(\d+)\t(\d+)\t([^\t]*)\t(.*)$')) {
    $id = [int]$m.Groups[1].Value
    $items[$id] = [pscustomobject]@{
        q   = [int]$m.Groups[2].Value
        gfx = $m.Groups[3].Value
        n   = $m.Groups[4].Value.Trim()
    }
    $count++
}
if ($items.Count -eq 0) {
    Write-Host "日志里没找到名字表。" -ForegroundColor Yellow
    Write-Host "  1) 确认 mod 是带 dump.itemNames 的版本（已部署）"
    Write-Host "  2) 启动游戏、进一局（第一次进房时会自动导出）"
    exit 2
}

# 探针行（看 GetLocalizedString 到底通不通）
$probe = [regex]::Match($text, '(?m)^\[INFO\] - Lua Debug: \[HIGHLIGHT\] \[DUMP\] GetLocalizedString 探针：(.*)$')
if ($probe.Success) { Write-Host ("探针: " + $probe.Groups[1].Value) -ForegroundColor DarkGray }

$sorted = $items.GetEnumerator() | Sort-Object Key

# ---- 写 Lua 表（离线册子用，零解析）----
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("-- 自动生成，别手改。来源：tools\items-json.ps1")
[void]$sb.AppendLine("return {")
foreach ($kv in $sorted) {
    $v = $kv.Value
    $n = $v.n.Replace('\', '\\').Replace('"', '\"')
    $g = $v.gfx.Replace('"', '\"')
    [void]$sb.AppendLine(('  [{0}]={{q={1},gfx="{2}",n="{3}"}},' -f $kv.Key, $v.q, $g, $n))
}
[void]$sb.AppendLine("}")
$luaPath = Join-Path $OutDir "items.lua"
[System.IO.File]::WriteAllText($luaPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

# ---- 写 JSON ----
$jsonObj = [ordered]@{}
foreach ($kv in $sorted) { $jsonObj[[string]$kv.Key] = $kv.Value }
$jsonPath = Join-Path $OutDir "items.json"
$jsonObj | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host ""
Write-Host ("道具名表: {0} 个道具（本次从日志提取 {1} 行，重复行已覆盖）" -f $items.Count, $count) -ForegroundColor Green
Write-Host ("  {0}" -f $luaPath) -ForegroundColor Green
Write-Host ("  {0}" -f $jsonPath) -ForegroundColor Green

# 抽样看看
Write-Host ""
Write-Host "抽样（前 6 个有名子的）:" -ForegroundColor Cyan
$shown = 0
foreach ($kv in $sorted) {
    if ($kv.Value.n -ne "") {
        Write-Host ("  {0,-5} Q{1}  {2}" -f $kv.Key, $kv.Value.q, $kv.Value.n)
        $shown++
        if ($shown -ge 6) { break }
    }
}
if ($shown -eq 0) { Write-Host "  ⚠ 全是空名子 —— GetLocalizedString 可能不接受带 # 的 key" -ForegroundColor Yellow }
