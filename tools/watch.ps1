# =============================================================================
# watch.ps1 —— 常驻蹲守：检测到游戏进程启动时，自动归档一次
#
# 为什么需要它：游戏内的 mod 没法调外部进程（io/os 被沙箱移除），所以
# 从 Steam 直接启动游戏时，没有任何"mod 侧"的办法去做备份。
# 唯一可靠的方式是在系统层盯进程 —— 就是这个脚本。
#
# 行为：每 2 秒看一次 isaac-ng.exe；
#       · 首次出现 → 跑一次 archive.ps1（去重，所以重复跑无害）
#       · 已在运行 → 不重复归档
#       · 退出后 → 复位，等下一次启动
#
# 用法：
#   pwsh tools\watch.ps1            前台常驻（Ctrl+C 退出）
#   pwsh tools\watch.ps1 -Once      只扫一次就退出（用来测试）
#   pwsh tools\watch.ps1 -Install   装成"开机自启"（放启动文件夹，隐藏窗口）
#   pwsh tools\watch.ps1 -Uninstall 取消自启
# =============================================================================
param(
    [switch]$Once,
    [switch]$Install,
    [switch]$Uninstall,
    [int]$IntervalSec = 2
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Archive = Join-Path $PSScriptRoot "archive.ps1"
$LogFile = Join-Path $Root "_logs\watch.log"
$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$ShortcutPath = Join-Path $StartupDir "HighlightReview-Watch.lnk"

function Log([string]$msg) {
    if (-not (Test-Path (Split-Path $LogFile -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null
    }
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Invoke-Archive([string]$why) {
    if (-not (Test-Path $Archive)) { Log "找不到 archive.ps1"; return }
    Log ("归档开始（{0}）" -f $why)
    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Archive 2>&1
        Log ("归档完成：" + (($out | Where-Object { $_ -match "已有|新增" }) -join " "))
    } catch {
        Log ("归档失败：" + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- 安装/卸载自启
if ($Install) {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($ShortcutPath)
    $lnk.TargetPath = "powershell.exe"
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $lnk.WorkingDirectory = $Root
    $lnk.WindowStyle = 7
    $lnk.Save()
    Write-Host "已装成开机自启：" -ForegroundColor Green
    Write-Host "  $ShortcutPath"
    Write-Host "取消：pwsh tools\watch.ps1 -Uninstall"
    exit 0
}
if ($Uninstall) {
    if (Test-Path $ShortcutPath) { Remove-Item $ShortcutPath -Force; Write-Host "已取消自启" -ForegroundColor Green }
    else { Write-Host "没有装过自启" -ForegroundColor Yellow }
    exit 0
}

# ---------------------------------------------------------------- 主循环
$wasRunning = $false
Log ("蹲守启动（间隔 {0}s）" -f $IntervalSec)

while ($true) {
    $proc = Get-Process isaac-ng -ErrorAction SilentlyContinue
    $running = ($null -ne $proc)

    if ($running -and -not $wasRunning) {
        Log "检测到 isaac-ng.exe 启动"
        Invoke-Archive "检测到游戏启动"
        $wasRunning = $true
    } elseif (-not $running -and $wasRunning) {
        Log "isaac-ng.exe 已退出（不归档，按要求只在启动前备份）"
        $wasRunning = $false
    }

    if ($Once) {
        if (-not $running) { Write-Host "当前没有游戏在跑（-Once 只扫一次）" -ForegroundColor DarkGray }
        else { Write-Host "游戏正在运行" -ForegroundColor DarkGray }
        exit 0
    }

    Start-Sleep -Seconds $IntervalSec
}
