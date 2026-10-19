# =============================================================================
# check.ps1 —— 一键体检：跑完游戏后看看 mod 到底干了什么
#
# 用法：pwsh tools\check.ps1            # 看当前 log.txt
#       pwsh tools\check.ps1 -Session 2 # 看倒数第 2 次启动的日志
#       pwsh tools\check.ps1 -All       # 把所有历史日志的 HIGHLIGHT 行汇总
# =============================================================================
param([int]$Session = 1, [switch]$All, [int]$Tail = 40)

$ErrorActionPreference = "Stop"
$Docs = Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance"
$Game = "D:\LenovoSoftstore\Install\Steam\steamapps\common\The Binding of Isaac Rebirth"
$DataDir = Join-Path $Game "data\highlight-review"

function Show-Head($text) { Write-Host ""; Write-Host "== $text ==" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 选日志
$log = Join-Path $Docs "log.txt"
if ($Session -gt 1 -or $All) {
    $sessions = Get-ChildItem $Docs -Filter "isaacv*.txt" | Sort-Object LastWriteTime -Descending
    if ($sessions.Count -ge $Session) { $log = $sessions[$Session - 1].FullName }
}

Show-Head "日志：$log"
if (-not (Test-Path $log)) { Write-Host "找不到日志" -ForegroundColor Red; exit 2 }
Write-Host ("修改时间：{0}   大小：{1:N0} 字节" -f (Get-Item $log).LastWriteTime, (Get-Item $log).Length)

# ---------------------------------------------------------------- mod 是否加载
Show-Head "1) mod 是否被加载"
$loaded = Select-String -Path $log -Pattern "Highlight Review|\[HIGHLIGHT\] loaded" -ErrorAction SilentlyContinue
if ($loaded) {
    $loaded | Select-Object -First 3 | ForEach-Object { Write-Host "  " + $_.Line -ForegroundColor Green }
} else {
    Write-Host "  ✗ 日志里没有 Highlight Review 的痕迹" -ForegroundColor Red
    Write-Host "    → 检查：mods\highlight-review\ 是否存在、Mods 菜单里是否启用、" +
                 "metadata.xml 的 <directory> 是否等于 highlight-review"
}

# ---------------------------------------------------------------- 自检
Show-Head "2) 编解码自检"
Select-String -Path $log -Pattern "fmt 自检" -ErrorAction SilentlyContinue |
    Select-Object -Last 2 | ForEach-Object { Write-Host "  " + $_.Line }

# ---------------------------------------------------------------- 采集行
Show-Head "3) 采集行（最近 $Tail 条）"
$lines = Select-String -Path $log -Pattern "\[HIGHLIGHT\] (F\d|开局|收局|落盘|载入|续接)" -ErrorAction SilentlyContinue
if ($lines) {
    $lines | Select-Object -Last $Tail | ForEach-Object { Write-Host "  " + $_.Line }
    Write-Host ("  （共 {0} 条）" -f $lines.Count) -ForegroundColor DarkGray
} else {
    Write-Host "  ✗ 没有采集数据" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 错误
Show-Head "4) Lua 报错（最近 15 条）"
$errs = Select-String -Path $log -Pattern 'attempt to |stack traceback|Error in |Lua Error|\[string "' -ErrorAction SilentlyContinue |
    Where-Object { $_.Line -notmatch '^\[INFO\] - Lua mem usage' } |
    Select-Object -Last 15
if ($errs) {
    $errs | ForEach-Object { Write-Host "  " + $_.Line -ForegroundColor Red }
} else {
    Write-Host "  ✓ 没发现 Lua 报错" -ForegroundColor Green
}

# ---------------------------------------------------------------- 存档
Show-Head "5) 存档文件"
if (Test-Path $DataDir) {
    Get-ChildItem $DataDir -Filter "save*.dat" | ForEach-Object {
        $bytes = (Get-Content $_.FullName -Raw).Length
        Write-Host ("  {0,-12} {1,8} 字符  {2}" -f $_.Name, $bytes, $_.LastWriteTime) -ForegroundColor Green
        $first = Get-Content $_.FullName -TotalCount 1
        $runs = (Select-String -Path $_.FullName -Pattern "^R\|" | Measure-Object).Count
        Write-Host ("    魔数行: {0}   局数: {1}" -f $first, $runs) -ForegroundColor DarkGray
    }
} else {
    Write-Host "  ✗ 还没有 $DataDir" -ForegroundColor Yellow
    Write-Host "    （说明还没走到过保存点：局结束 或 退出游戏）"
}

# ---------------------------------------------------------------- DUMP
Show-Head "6) 数据面板"
$dumpLines = Select-String -Path $log -Pattern "\[HIGHLIGHT\] \[DUMP\]" -ErrorAction SilentlyContinue
if ($dumpLines) {
    Write-Host ("  共 {0} 行，前 8 行：" -f $dumpLines.Count) -ForegroundColor DarkGray
    $dumpLines | Select-Object -First 8 | ForEach-Object { Write-Host "  " + $_.Line }
} else {
    Write-Host "  （还没导出；进游戏第一次进房时会自动导出）" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "完成。" -ForegroundColor Cyan
