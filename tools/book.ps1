# =============================================================================
# book.ps1 —— 一键生成"离线册子"
#
#   pwsh tools\book.ps1            解析真实存档，输出 _logs\book-<时间>.txt
#   pwsh tools\book.ps1 -Demo      用造的数据生成样例（验证排版）
#
# 注意：册子的**内容逻辑**在 mod/core/highlight.lua + mod/core/text_render.lua，
# 游戏内册子将来调用的是同一份 highlight.lua，所以这里验证过的行为不会走样。
# =============================================================================
param([switch]$Demo, [switch]$Open)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Lu = Join-Path $PSScriptRoot "luarun.ps1"
$Target = if ($Demo) { Join-Path $Root "tests\book_demo.lua" } else { Join-Path $Root "tests\book_offline.lua" }

if (-not (Test-Path $Lu)) { throw "找不到 luarun.ps1" }
if (-not (Test-Path $Target)) { throw "找不到 $Target" }

# 先归档：把游戏里最近 10 局合并进永久档案，保证不会因为淘汰而丢数据
$arch = Join-Path $PSScriptRoot "archive.ps1"
if (Test-Path $arch) {
    Write-Host "归档中..." -ForegroundColor DarkGray
    & $arch
    Write-Host ""
}

Write-Host ("运行 " + (Split-Path $Target -Leaf) + " ...") -ForegroundColor Cyan
$out = & "C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
        -ExecutionPolicy Bypass -File $Lu $Target 2>&1
Write-Host $out

$latest = Get-ChildItem (Join-Path $Root "_logs") -Filter "*.txt" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ""
    Write-Host ("最新报告: {0}" -f $latest.FullName) -ForegroundColor Green
    Write-Host ("  {0:N0} 字节 / 修改于 {1}" -f $latest.Length, $latest.LastWriteTime) -ForegroundColor DarkGray
    if ($Open) {
        try {
            Invoke-Item $latest.FullName
            Write-Host ("已打开: " + $latest.FullName) -ForegroundColor Green
        } catch {
            Write-Host ("自动打开失败（{0}），请手动打开: {1}" -f $_.Exception.Message, $latest.FullName) -ForegroundColor Yellow
        }
    }
}
