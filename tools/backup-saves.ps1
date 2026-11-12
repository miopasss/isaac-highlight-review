# =============================================================================
# backup-saves.ps1 -- 无窗口版存档快照（给计划任务/命令行用）
#
#   -Once        跑一轮（计划任务调这个）
#   -Status      看任务状态 + 最近快照
#   -Install     注册隐藏的计划任务（每 -EveryMinutes 分钟）
#   -Uninstall   删任务
#
# 来源与间隔读 tools\watch-sources.json —— 和可见窗口版 save-watch.ps1 共用同一份配置。
# 现在的主方案是窗口版（install-watch.ps1）；这里是“没开窗口也要有人备份”的兜底。
# =============================================================================
param(
    [switch]$Once,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [int]$EveryMinutes = 10,
    [string]$Config = "",
    [string]$Root = ""
)

$ErrorActionPreference = "Continue"
$TaskName = "IsaacSaveBackup"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
if (-not $Config) { $Config = Join-Path $PSScriptRoot "watch-sources.json" }
if (-not $Root) { $Root = Join-Path $ProjectRoot "_logs\save-backup" }
. (Join-Path $PSScriptRoot "save-lib.ps1")

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

function Invoke-Once {
    $isaac = Get-IsaacDirSafe
    if (-not $isaac) { Say "找不到游戏目录" Red; return 1 }
    $sources = @()
    try { $sources = @(Get-Sources $Config $isaac) }
    catch { Say ("配置读不出来：" + $_.Exception.Message) Red; return 1 }

    $savedAll = 0; $badAll = 0
    foreach ($s in $sources) {
        $r = Invoke-Source $s $Root
        foreach ($e in $r.Events) {
            $c = if ($e.Kind -eq "ok") { "Green" } elseif ($e.Kind -eq "bad") { "Red" } elseif ($e.Kind -eq "warn") { "Yellow" } else { "DarkGray" }
            Say ("  " + $e.Text) $c
        }
        if ($r.Events.Count -eq 0) { Say ("  {0} 未变（{1} 个文件）" -f $s.name, $r.Total) DarkGray }
        Add-BackupLog $Root ("[{0}] 新增 {1} 未变 {2} 失败 {3}" -f $s.name, $r.Saved, $r.Same, $r.Bad)
        $savedAll += $r.Saved; $badAll += $r.Bad
    }
    Say ("本次：新增 {0}，失败 {1}" -f $savedAll, $badAll)
    return 0
}

function Show-Status {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName
        Say ("任务：{0}  状态 {1}" -f $TaskName, $t.State) Green
        Say ("  上次运行 {0}  结果 0x{1:X}  下次 {2}" -f $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime)
    } else {
        Say "计划任务未安装（主方案是 save-watch 窗口，用 install-watch.ps1 装）" Yellow
    }
    $autoDir = Join-Path $Root "auto"
    $dailyDir = Join-Path $Root "daily"
    $auto = @(Get-ChildItem $autoDir -Filter "*.dat" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $daily = @(Get-ChildItem $dailyDir -Filter "*.dat" -File -ErrorAction SilentlyContinue)
    $mb = (($auto | Measure-Object Length -Sum).Sum + ($daily | Measure-Object Length -Sum).Sum) / 1MB
    Say ("快照：auto {0} 份 / daily {1} 份 / 合计 {2:N1} MB" -f $auto.Count, $daily.Count, $mb)
    $auto | Select-Object -First 6 | ForEach-Object { Say ("  {0}  {1,10:N0}  {2}" -f $_.LastWriteTime.ToString("MM-dd HH:mm:ss"), $_.Length, $_.Name) }
    Say ("日志：{0}" -f (Join-Path $Root "backup.log"))
    return 0
}

function Install-Task {
    $vbs = Join-Path $PSScriptRoot "backup-saves.vbs"
    if (-not (Test-Path -LiteralPath $vbs)) { Say "缺少 backup-saves.vbs" Red; return 1 }
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + $vbs + '"')
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
        -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -Hidden
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description "以撒 mod 存档快照（隐藏）：每 $EveryMinutes 分钟备份到 _logs\save-backup" -Force -ErrorAction Stop | Out-Null
    } catch {
        Say ("注册失败：" + $_.Exception.Message) Red
        return 1
    }
    Say ("已注册隐藏任务 {0}（每 {1} 分钟）" -f $TaskName, $EveryMinutes) Green
    Say "注意：它会和可见窗口版重复备份，二者留一个即可" Yellow
    return 0
}

function Uninstall-Task {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Say ("已删除任务 {0}" -f $TaskName) Green
    } else { Say "任务不存在" Yellow }
    return 0
}

if ($Uninstall) { exit (Uninstall-Task) }
if ($Install)   { exit (Install-Task) }
if ($Status)    { exit (Show-Status) }
exit (Invoke-Once)
