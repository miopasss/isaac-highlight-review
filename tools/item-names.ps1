# =============================================================================
# item-names.ps1 —— 从 EID 的中文名表生成 _logs\items.lua / items.json
#
# 为什么用 EID：游戏自身的本地化文本是打包的（ResourceExtractor 才能解），
# 而 EID 把 id → 中文名维护成了明文的 Lua 表：
#   descriptions\names\zh_cn.lua
#     [C_ID .. 118] = "魔鬼之书", -- The Book of Belial
#
# 输出格式和 dump 导出的那套一致，离线册子直接读 _logs\items.lua。
#
# 用法：pwsh tools\item-names.ps1
# =============================================================================
param(
    [string]$EidPath = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot "_logs" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

if (-not $EidPath) {
    $eidDir = Get-ChildItem (Join-Path $IsaacDir "mods") -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match "external item descriptions" } | Select-Object -First 1
    if (-not $eidDir) { throw "找不到 EID mod（external item descriptions）" }
    $EidPath = Join-Path $eidDir.FullName "descriptions\names\zh_cn.lua"
}
if (-not (Test-Path $EidPath)) { throw "找不到名表: $EidPath" }

Write-Host "读名表..." -ForegroundColor DarkGray
$text = [System.IO.File]::ReadAllText($EidPath, [System.Text.Encoding]::UTF8)

$names = @{}
$count = 0
# 形如：    [C_ID .. 118] = "魔鬼之书", -- The Book of Belial
foreach ($m in [regex]::Matches($text, '\[\s*C_ID\s*\.\.\s*(\d+)\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"')) {
    $id = [int]$m.Groups[1].Value
    $name = $m.Groups[2].Value.Replace('\"', '"').Replace('\\', '\')
    if ($name -ne "") { $names[$id] = $name; $count++ }
}

if ($names.Count -eq 0) { throw "没解析出任何道具名，EID 名表格式可能变了" }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("-- 自动生成，别手改。来源：tools\item-names.ps1（EID 中文名表）")
[void]$sb.AppendLine("return {")
foreach ($id in ($names.Keys | Sort-Object)) {
    $n = $names[$id].Replace('\', '\\').Replace('"', '\"')
    [void]$sb.AppendLine(('  [{0}]={{n="{1}"}},' -f $id, $n))
}
[void]$sb.AppendLine("}")
$luaPath = Join-Path $OutDir "items.lua"
[System.IO.File]::WriteAllText($luaPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$jsonObj = [ordered]@{}
foreach ($id in ($names.Keys | Sort-Object)) { $jsonObj[[string]$id] = $names[$id] }
$jsonPath = Join-Path $OutDir "items.json"
$jsonObj | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host ""
Write-Host ("解析出 {0} 个道具中文名（原名表 {1:N0} 字节）" -f $names.Count, (Get-Item $EidPath).Length) -ForegroundColor Green
Write-Host ("  {0}" -f $luaPath) -ForegroundColor Green
Write-Host ("  {0}" -f $jsonPath) -ForegroundColor Green
Write-Host ""
Write-Host "抽样:" -ForegroundColor Cyan
foreach ($id in @(118, 1052, 313, 262, 1, 33)) {
    if ($names.ContainsKey($id)) { Write-Host ("  {0,-5} {1}" -f $id, $names[$id]) }
}
