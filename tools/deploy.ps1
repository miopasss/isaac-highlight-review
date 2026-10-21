# =============================================================================
# deploy.ps1 —— 把两个 mod 同步到游戏 mods 目录
#
# 用法：
#   powershell -File tools\deploy.ps1              # 两个都同步
#   powershell -File tools\deploy.ps1 -Mod rating  # 只同步评级 mod
#   powershell -File tools\deploy.ps1 -Mod review  # 只同步回顾 mod
#   powershell -File tools\deploy.ps1 -Clean       # 先删目标再同步
#
# 目标文件夹名必须与各自 metadata.xml 的 <directory> 一致：
#   mod-review → highlight-review
#   mod-rating → highlight-rating
#
# 同步前会先把 shared\ 里的文件复制进两个 mod（游戏沙箱不能跨 mod require）。
# =============================================================================
param(
    [ValidateSet("both", "review", "rating")]
    [string]$Mod = "both",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"

$GameDir = $IsaacDir
$Root    = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $GameDir)) { throw "找不到游戏目录: $GameDir" }

# ── 1) 把 shared\ 复制进每个 mod ────────────────────────────────────────────
$Shared = Join-Path $Root "shared"
$targets = @()
if ($Mod -in @("both", "review")) { $targets += @{ Src = "mod-review"; Dir = "highlight-review" } }
if ($Mod -in @("both", "rating")) { $targets += @{ Src = "mod-rating"; Dir = "highlight-rating" } }

if (Test-Path $Shared) {
    $sharedFiles = Get-ChildItem -Path $Shared -Recurse -File
    foreach ($t in $targets) {
        foreach ($f in $sharedFiles) {
            $rel = $f.FullName.Substring($Shared.Length).TrimStart('\')
            $dest = Join-Path (Join-Path $Root $t.Src) $rel
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item -Path $f.FullName -Destination $dest -Force
        }
    }
    Write-Host ("shared\ 已同步到 {0} 个 mod（{1} 个文件）" -f $targets.Count, $sharedFiles.Count)
}

# ── 2) 逐个 mod 复制到游戏 ──────────────────────────────────────────────────
$exts = @(".lua", ".xml", ".txt", ".png", ".anm2", ".fnt", ".ttf", ".ogg", ".wav", ".json")

foreach ($t in $targets) {
    $source = Join-Path $Root $t.Src
    $target = Join-Path $GameDir ("mods\" + $t.Dir)

    if (-not (Test-Path $source)) { throw "源目录不存在: $source" }

    if ($Clean -and (Test-Path $target)) { Remove-Item -Path $target -Recurse -Force }
    if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }

    $items = Get-ChildItem -Path $source -Recurse -File | Where-Object { $_.Extension -in $exts }
    $copied = 0
    foreach ($f in $items) {
        $rel = $f.FullName.Substring($source.Length).TrimStart('\')
        $dest = Join-Path $target $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $copied++
    }
    Write-Host ("已同步 {0} 个文件 -> {1}" -f $copied, $target)

    # 清理：目标里存在、但源里已经没有的文件（拆分/删文件后必须清，否则旧模块还在）
    $copiedRel = @{}
    foreach ($f in $items) { $copiedRel[$f.FullName.Substring($source.Length).TrimStart('\\')] = $true }
    $pruned = 0
    foreach ($f in (Get-ChildItem -Path $target -Recurse -File)) {
        if ($f.Extension -notin $exts) { continue }
        $rel = $f.FullName.Substring($target.Length).TrimStart('\\')
        if (-not $copiedRel.ContainsKey($rel)) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            $pruned++
        }
    }
    if ($pruned -gt 0) { Write-Host ("  清理了 {0} 个残留文件（源里已没有）" -f $pruned) -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "接下来：" -ForegroundColor Cyan
Write-Host "  1. 启动游戏"
Write-Host "  2. 进一局随便打几个房间"
Write-Host "  3. 看日志：`"$env:USERPROFILE\Documents\My Games\Binding of Isaac Repentance\log.txt`""
Write-Host "     搜 [HIGHLIGHT]（回顾）或者 [WEIGHT]（评级）"
Write-Host "  4. 存档：$GameDir\data\highlight-review\ 和 $GameDir\data\highlight-rating\"
