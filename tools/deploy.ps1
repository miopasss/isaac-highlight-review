# =============================================================================
# deploy.ps1 —— 把 mod/ 同步到游戏的 mods 目录
#
# 用法：
#   pwsh tools\deploy.ps1          # 同步
#   pwsh tools\deploy.ps1 -Clean   # 先删目标再同步（清掉残留文件）
#
# 注意：目标文件夹名必须与 metadata.xml 的 <directory> 一致（highlight-review）。
# =============================================================================
param([switch]$Clean)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_paths.ps1"
$GameDir = $IsaacDir
$ModName  = "highlight-review"
$Source   = Join-Path (Split-Path $PSScriptRoot -Parent) "mod"
$Target   = Join-Path $GameDir "mods\$ModName"

if (-not (Test-Path $Source)) { throw "源目录不存在: $Source" }
if (-not (Test-Path $GameDir)) { throw "找不到游戏目录: $GameDir" }

if ($Clean -and (Test-Path $Target)) {
    Write-Host "删除旧目录: $Target"
    Remove-Item -Path $Target -Recurse -Force
}
if (-not (Test-Path $Target)) { New-Item -ItemType Directory -Path $Target | Out-Null }

# 只同步 .lua / .xml / .txt，跳过测试与工具
$items = Get-ChildItem -Path $Source -Recurse -File |
    Where-Object { $_.Extension -in @(".lua", ".xml", ".txt", ".png", ".anm2") }

$copied = 0
foreach ($f in $items) {
    $rel = $f.FullName.Substring($Source.Length).TrimStart('\')
    $dest = Join-Path $Target $rel
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item -Path $f.FullName -Destination $dest -Force
    $copied++
}

Write-Host "已同步 $copied 个文件 -> $Target"
Write-Host ""
Write-Host "接下来：" -ForegroundColor Cyan
Write-Host "  1. 启动游戏（用 REPENTOGONLauncher）"
Write-Host "  2. 进一局随便打几个房间"
Write-Host "  3. 看日志：`"$env:USERPROFILE\Documents\My Games\Binding of Isaac Repentance\log.txt`""
Write-Host "     搜 [HIGHLIGHT]"
Write-Host "  4. 退出游戏后看存档：$GameDir\data\$ModName\save1.dat"
