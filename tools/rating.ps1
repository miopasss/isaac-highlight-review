# =============================================================================
# rating.ps1 —— 从 saveN.dat 里取出自定义评级表（局外解析）
#
# 评级表存在存档里的一行：
#   Q={"v":1,"e":{"118":{"q":3.5,"w":2}}}
#
# 用法：
#   .\tools\rating.ps1                 # 列出所有槽的评级
#   .\tools\rating.ps1 -Slot 3 -Json   # 只输出 3 号槽的原始 JSON
# =============================================================================
[CmdletBinding()]
param([int]$Slot = 0, [switch]$Json)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

. (Join-Path $PSScriptRoot "_paths.ps1")
$dataDir = Join-Path $IsaacDir "data\highlight-review"

if (-not (Test-Path $dataDir)) { Write-Host "  没有数据目录: $dataDir"; exit 1 }

function Get-RatingJson([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if ($line.StartsWith("Q=")) { return $line.Substring(2) }
    }
    return $null
}

$slots = if ($Slot -gt 0) { @($Slot) } else { @(1, 2, 3) }
$found = 0
foreach ($s in $slots) {
    $p = Join-Path $dataDir ("save{0}.dat" -f $s)
    $j = Get-RatingJson $p
    if ($null -eq $j) { continue }
    $found++
    $obj = $null
    try { $obj = $j | ConvertFrom-Json } catch { }

    if ($Json) { Write-Output $j; continue }

    Write-Host ""
    Write-Host ("=== save{0}.dat ===" -f $s) -ForegroundColor Cyan
    if (-not $obj) { Write-Host "  JSON 解析失败，原文：$j"; continue }
    $ids = @($obj.e.PSObject.Properties.Name)
    Write-Host ("  共 {0} 条覆盖" -f $ids.Count)
    if ($ids.Count -eq 0) { continue }
    $rows = foreach ($id in ($ids | Sort-Object { [int]$_ })) {
        $e = $obj.e.$id
        [pscustomobject]@{
            Id     = [int]$id
            Q      = $e.q
            W      = $e.w
            启用   = if ($null -eq $e.on) { $true } else { [bool]$e.on }
        }
    }
    $rows | Format-Table -AutoSize | Out-String | Write-Host
}

if ($found -eq 0 -and -not $Json) { Write-Host "  没有任何槽存在评级数据" }