# =============================================================================
# check-proxy.ps1 —— 代理自检：节点活没活，一眼看出来
#
# 用法：pwsh tools\check-proxy.ps1
#       pwsh tools\check-proxy.ps1 -Proxy "http://127.0.0.1:7890"
#
# 判断逻辑：国内站本来就直连能通，所以**只有境外站才算数**。
# =============================================================================
param(
    [string]$Proxy = "http://127.0.0.1:7890",
    [int]$Timeout = 20
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "代理: $Proxy" -ForegroundColor Cyan
Write-Host ("=" * 62)

# 端口是否在监听
$m = [regex]::Match($Proxy, ':(\d+)\s*$')
$port = if ($m.Success) { [int]$m.Groups[1].Value } else { 7890 }
$listen = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($listen) {
    $pid_ = ($listen | Select-Object -First 1).OwningProcess
    $proc = Get-Process -Id $pid_ -ErrorAction SilentlyContinue
    Write-Host ("端口 {0} : 在监听  (PID {1} {2})" -f $port, $pid_, $proc.ProcessName) -ForegroundColor Green
} else {
    Write-Host ("端口 {0} : 没有进程监听 —— 代理没启动" -f $port) -ForegroundColor Red
}

# 目标站点
$targets = @(
    @{ Name = "baidu.com        (国内基准)"; Url = "https://www.baidu.com";            Expect = $true  },
    @{ Name = "gstatic 204      (连通性)"; Url = "https://www.gstatic.com/generate_204"; Expect = $true },
    @{ Name = "steamcommunity   (工坊)";   Url = "https://steamcommunity.com";        Expect = $true  },
    @{ Name = "github.com";                Url = "https://github.com";                Expect = $true  },
    @{ Name = "bindingofisaacrebirth.wiki"; Url = "https://bindingofisaacrebirth.wiki.gg"; Expect = $true }
)

Write-Host ("-" * 62)
$okCount = 0
$intlOK  = 0
foreach ($t in $targets) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time $Timeout -x $Proxy --ssl-no-revoke $t.Url 2>$null
    $sw.Stop()
    $good = ($code -match "^[23]")
    if ($good) { $okCount++ }
    if ($good -and $t.Name -notmatch "国内基准") { $intlOK++ }
    $color = if ($good) { "Green" } else { "Red" }
    $ms = "{0,6:N0} ms" -f $sw.Elapsed.TotalMilliseconds
    Write-Host ("  {0,-38} {1,-5} {2}" -f $t.Name, $code, $ms) -ForegroundColor $color
}

Write-Host ("-" * 62)
if ($intlOK -gt 0) {
    Write-Host "结论：境外可达，代理可用。" -ForegroundColor Green
} elseif ($okCount -gt 0) {
    Write-Host "结论：只有国内通。代理在跑，但境外出口不通。" -ForegroundColor Red
    Write-Host "      常见原因：节点失效 / 订阅过期 / 处于直连模式。" -ForegroundColor Yellow
    Write-Host "      去 Clash 换节点或更新订阅，再跑一次本脚本。" -ForegroundColor Yellow
} else {
    Write-Host "结论：全都不通，代理本身有问题。" -ForegroundColor Red
}

# 顺便看看 Clash 的活跃配置有多旧
$profiles = Join-Path $env:USERPROFILE ".config\clash\profiles"
if (Test-Path $profiles) {
    $latest = Get-ChildItem $profiles -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $age = (Get-Date) - $latest.LastWriteTime
        Write-Host ""
        Write-Host ("最新订阅文件: {0}   更新于 {1}  （{2:N0} 天前）" -f `
            $latest.Name, $latest.LastWriteTime, $age.TotalDays) -ForegroundColor $(if ($age.TotalDays -gt 90) { "Red" } else { "DarkGray" })
        if ($age.TotalDays -gt 90) {
            Write-Host "  ⚠ 超过 90 天没更新订阅，免费节点基本已经失效。" -ForegroundColor Yellow
        }
    }
}
Write-Host ""
