# =============================================================================
# sync-rating.ps1 —— 把当前槽的评级表同步到其他存档槽
#
# 编辑器只写"当前槽"的 saveN.dat（游戏不给跨槽写入的 API），
# 这个脚本在局外把 Q= 那一行复制到另外两个槽，做到"看起来全局"。
#
# 用法：
#   .\tools\sync-rating.ps1 -From 3          # 以 3 号槽为准，覆盖 1、2
#   .\tools\sync-rating.ps1 -From 3 -DryRun  # 只看会改什么
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 3)][int]$From,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

. (Join-Path $PSScriptRoot "_paths.ps1")
$dataDir = Join-Path $IsaacDir "data\highlight-review"
$srcPath = Join-Path $dataDir ("save{0}.dat" -f $From)

if (-not (Test-Path $srcPath)) { Write-Host "  ✘ 源槽不存在: $srcPath" -ForegroundColor Red; exit 1 }

# 取源 Q= 行
$qLine = $null
foreach ($line in [System.IO.File]::ReadAllLines($srcPath, [System.Text.Encoding]::UTF8)) {
    if ($line.StartsWith("Q=")) { $qLine = $line; break }
}
if (-not $qLine) { Write-Host "  ✘ 源槽里没有评级数据（Q= 行）" -ForegroundColor Red; exit 1 }
Write-Host ("  源: save{0}.dat   {1} 字节的评级数据" -f $From, $qLine.Length)

# 备份目录
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bak = Join-Path $PSScriptRoot ("..\_backup\sync-rating-" + $stamp)
New-Item -ItemType Directory -Path $bak -Force | Out-Null

foreach ($s in @(1, 2, 3)) {
    if ($s -eq $From) { continue }
    $dst = Join-Path $dataDir ("save{0}.dat" -f $s)

    if (-not (Test-Path $dst)) {
        Write-Host ("  - save{0}.dat 不存在，跳过（进一次该存档槽后再同步）" -f $s) -ForegroundColor Yellow
        continue
    }

    Copy-Item $dst (Join-Path $bak ("save{0}.dat" -f $s)) -Force
    $lines = [System.IO.File]::ReadAllLines($dst, [System.Text.Encoding]::UTF8)
    $kept = @($lines | Where-Object { -not $_.StartsWith("Q=") })
    $kept += $qLine

    if ($DryRun) {
        Write-Host ("  [DryRun] save{0}.dat: {1} 行 → {2} 行" -f $s, $lines.Count, $kept.Count) -ForegroundColor Cyan
    } else {
        [System.IO.File]::WriteAllLines($dst, $kept, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("  ✔ save{0}.dat 已同步（备份在 _backup\sync-rating-{1}）" -f $s, $stamp) -ForegroundColor Green
    }
}
Write-Host ""
Write-Host "  完成。游戏里切到该槽后评级即生效（重启游戏才读档）。"