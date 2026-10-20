# =============================================================================
# pr.ps1 —— 功能分支 → Pull Request → squash 合并（一条命令走完）
#
# 作者要求：main 上每个功能只占一个节点，细节留在功能分支里。
# 本脚本就是那个"一个节点"的制造机。
#
# 用法：
#   # 只建 PR（不合并）
#   .\tools\pr.ps1 -Branch feature/ui-v0.3 -Title "增加XX（feature/ui-v0.3）"
#
#   # 建 PR 并立即 squash 合并，然后删除远端分支
#   .\tools\pr.ps1 -Branch feature/ui-v0.3 -Title "增加XX（feature/ui-v0.3）" -Merge -DeleteBranch
#
#   # 看现有 PR
#   .\tools\pr.ps1 -List
#
#   # 只合并已有的 PR
#   .\tools\pr.ps1 -MergeOnly 1
#
# token：默认读 tools\.gh_token（明文一行），也可以用 -Token 或环境变量 GH_TOKEN 覆盖。
#       该文件已进 .gitignore —— 别提交，GitHub 会自动撤销公开仓库里泄露的 token。
# =============================================================================
[CmdletBinding()]
param(
    [string]$Branch,
    [string]$Title,
    [string]$Base = "main",
    [string]$Body,
    [string]$Token,
    [int]$MergeOnly = 0,
    [switch]$Merge,
    [switch]$DeleteBranch,
    [switch]$List,
    [switch]$Draft
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# git 会把进度写到 stderr；在 $ErrorActionPreference=Stop 下会被当成终止性错误。
# 所有 git 调用都走这个封装，把输出当普通文本收。
function GitOut {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args2)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { return (& git @Args2 2>&1) } finally { $ErrorActionPreference = $prev }
}

function Info($m) { Write-Host "  $m" }
function Ok($m)   { Write-Host "  ✔ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  ✘ $m" -ForegroundColor Red; exit 1 }

# ── token ────────────────────────────────────────────────────────────────────
if (-not $Token) { $Token = $env:GH_TOKEN }
if (-not $Token) {
    $p = Join-Path $PSScriptRoot ".gh_token"
    if (Test-Path $p) { $Token = (Get-Content $p -Raw).Trim() }
}
if (-not $Token -and -not $List) { Die "没有 token。放到 tools\.gh_token，或用 -Token / 环境变量 GH_TOKEN。" }

# ── 仓库信息（从 origin 推断 owner/repo）─────────────────────────────────────
$remoteUrl = GitOut remote get-url origin
if (-not $remoteUrl) { Die "找不到 origin 远端" }
if ($remoteUrl -match '[:/]([^/:]+)/([^/]+?)(\.git)?$') {
    $owner = $Matches[1]; $repo = $Matches[2]
} else { Die "解析不了远端地址: $remoteUrl" }
$api = "https://api.github.com/repos/$owner/$repo"
Info "仓库: $owner/$repo"

$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = "application/vnd.github+json"
    "User-Agent"           = "highlight-review-pr"
    "X-GitHub-Api-Version" = "2022-11-28"
}

function Api($method, $path, $obj) {
    $uri = "$api$path"
    if ($obj -ne $null) {
        $json = $obj | ConvertTo-Json -Depth 8 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        return Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $bytes `
            -ContentType "application/json; charset=utf-8" -TimeoutSec 40
    }
    return Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -TimeoutSec 40
}

# ── -List ────────────────────────────────────────────────────────────────────
if ($List) {
    Info "拉取 PR 列表…"
    $prs = Api GET "/pulls?state=all&per_page=20" $null
    if (-not $prs -or $prs.Count -eq 0) { Warn "还没有任何 PR"; exit 0 }
    foreach ($p in $prs) {
        $state = if ($p.merged_at) { "已合并" } elseif ($p.state -eq "open") { "开启" } else { "关闭" }
        $d = $p
        if ($null -eq $p.changed_files) {
            try { $d = Api GET "/pulls/$($p.number)" $null } catch { $d = $p }
        }
        Write-Host ("  #{0,-3} [{1,-4}] {2}" -f $p.number, $state, $p.title)
        Write-Host ("        {0} → {1}   改动 {2} 文件 +{3}/-{4}" -f $d.head.ref, $d.base.ref, $d.changed_files, $d.additions, $d.deletions)
        Write-Host ("        {0}" -f $p.html_url)
    }
    exit 0
}

# ── 合并逻辑（供两条路径复用）───────────────────────────────────────────────
function Merge-PR([int]$num, [string]$title, [string]$msg) {
    Info "squash 合并 PR #$num …"
    $payload = @{ merge_method = "squash" }
    if ($title) { $payload.commit_title = $title }
    if ($msg)   { $payload.commit_message = $msg }
    $r = Api PUT "/pulls/$num/merge" $payload
    if (-not $r.merged) { Die "合并失败: $($r.message)" }
    Ok "已合并，合并提交 $($r.sha.Substring(0,7))"
    return $r.sha
}

function Sync-Main {
    Info "同步本地 main …"
    GitOut fetch origin | Out-Null
    $cur = (GitOut rev-parse --abbrev-ref HEAD | Select-Object -First 1).Trim()
    if ($cur -ne "main") { GitOut checkout main | Out-Null }
    GitOut reset --hard origin/main | Out-Null
    Ok ("main 现在: " + (GitOut log --oneline -1 | Select-Object -First 1))
}

# ── -MergeOnly <number> ─────────────────────────────────────────────────────
if ($MergeOnly -gt 0) {
    $pr = Api GET "/pulls/$MergeOnly" $null
    if ($pr.merged_at) { Warn "PR #$MergeOnly 已经合并过了"; exit 0 }
    Merge-PR $MergeOnly $Title $Body | Out-Null
    Sync-Main
    if ($DeleteBranch) {
        Info "删除远端分支 $($pr.head.ref) …"
        try { Api DELETE "/git/refs/heads/$($pr.head.ref)" $null | Out-Null; Ok "已删除" }
        catch { Warn "删除失败（可能已删除）: $($_.Exception.Message)" }
    }
    exit 0
}

# ── 建 PR（默认路径）────────────────────────────────────────────────────────
if (-not $Branch) { Die "必须给 -Branch（或用 -List / -MergeOnly）" }
if (-not $Title)  { Die "必须给 -Title（它会成为 PR 标题和 squash 提交标题）" }

# 本地分支必须存在，且已推送
$exists = (GitOut rev-parse --verify "refs/heads/$Branch")
if (-not $exists) { Die "本地没有分支 $Branch" }

Info "推送分支 $Branch …"
GitOut push -u origin $Branch | Where-Object { $_ -match "->" } | ForEach-Object { Info $_ }

# 已经存在同 head/base 的开放 PR？直接复用
$open = Api GET "/pulls?state=open&head=$owner`:$Branch&base=$Base" $null
if ($open -and $open.Count -gt 0) {
    $pr = $open[0]
    Warn "已存在 PR #$($pr.number)，复用"
} else {
    if (-not $Body) {
        $commits = (GitOut log --oneline "$Base..$Branch" | Measure-Object).Count
        $Body = "本 PR 由 tools\pr.ps1 创建。`n`n- 分支：``$Branch`` → ``$Base``" + "`n- 提交数：$commits"
    }
    $payload = @{ title = $Title; head = $Branch; base = $Base; body = $Body }
    if ($Draft) { $payload.draft = $true }
    Info "创建 PR …"
    $pr = Api POST "/pulls" $payload
    Ok "PR #$($pr.number) 已创建：$($pr.html_url)"
    Info ("改动: {0} 文件  +{1}/-{2}  提交 {3}" -f $pr.changed_files, $pr.additions, $pr.deletions, $pr.commits)
}

if (-not $Merge) {
    Info "只建了 PR，没有合并。要合并请加 -Merge"
    exit 0
}

# 合并前等 GitHub 算完可合并状态
for ($i = 0; $i -lt 10; $i++) {
    $st = Api GET "/pulls/$($pr.number)" $null
    if ($st.mergeable_state -and $st.mergeable_state -ne "unknown") { break }
    Start-Sleep -Milliseconds 800
}
if ($st.mergeable_state -eq "dirty") { Die "有冲突，无法合并（mergeable_state=dirty）" }

Merge-PR $pr.number $Title $null | Out-Null
Sync-Main

if ($DeleteBranch) {
    Info "删除远端分支 $Branch …"
    try { Api DELETE "/git/refs/heads/$Branch" $null | Out-Null; Ok "已删除远端分支" }
    catch { Warn "删除失败: $($_.Exception.Message)" }
}

Write-Host ""
Ok "完成。main 上新增一个节点：$Title"
