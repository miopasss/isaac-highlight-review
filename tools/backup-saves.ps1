# =============================================================================
# backup-saves.ps1 -- 定时把两个 mod 的存档快照到 _logs\save-backup\
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup-saves.ps1 -Once
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup-saves.ps1 -Install
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup-saves.ps1 -Uninstall
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup-saves.ps1 -Status
#
# 为什么不在游戏里做：
#   mod 自己的 saveData() 只解决"当前局最多丢一层"，
#   解决不了 1.2MB 预算淘汰旧局，也解决不了写盘途中游戏崩 —— 只有外部快照能兜住。
#
# 快照策略：
#   auto\  每次内容变化存一份（同名同内容只留一份），滚动保留 -Keep 份（默认 100）
#   daily\ 每个来源每天第一份，保留 -KeepDays 天（默认 60）
#   latest\ 永远只留最新一份，方便手动恢复
#
# 只读，不碰游戏目录里的任何文件。
# =============================================================================
param(
    [switch]$Once,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [int]$EveryMinutes = 10,
    [int]$Keep = 100,
    [int]$KeepDays = 60,
    [string]$BackupRoot = ""
)

$ErrorActionPreference = "Continue"
$TaskName = "IsaacSaveBackup"

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# ---------------------------------------------------------------- 路径
$ProjectRoot = Split-Path $PSScriptRoot -Parent
if (-not $BackupRoot) { $BackupRoot = Join-Path $ProjectRoot "_logs\save-backup" }
$AutoDir   = Join-Path $BackupRoot "auto"
$DailyDir  = Join-Path $BackupRoot "daily"
$LatestDir = Join-Path $BackupRoot "latest"
$LogFile   = Join-Path $BackupRoot "backup.log"
New-Item -ItemType Directory -Force -Path $AutoDir, $DailyDir, $LatestDir | Out-Null

function Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Say ("  " + $msg)
}

function Find-IsaacDir {
    try {
        . (Join-Path $PSScriptRoot "_paths.ps1")
        return $IsaacDir
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------- 读盘 / 校验
function Read-Bytes([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = [int]$fs.Length
            $buf = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) {
                $n = $fs.Read($buf, $read, $len - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            if ($read -eq $len) { return $buf }
        } finally { $fs.Dispose() }
    } catch { }
    return $null
}

function Read-Blob([string]$path) {
    # 游戏写盘时可能读到"写了一半"的文件：连读两次，内容一致才算稳定。
    # 存档没有结尾换行，没法靠长度判断，只能靠两次一致 + 魔数 + 结构。
    for ($i = 1; $i -le 4; $i++) {
        $a = Read-Bytes $path
        if ($null -eq $a) { Start-Sleep -Milliseconds 600; continue }
        Start-Sleep -Milliseconds 250
        $b = Read-Bytes $path
        if ($null -ne $b -and $a.Length -eq $b.Length -and (Get-Sha256 $a) -eq (Get-Sha256 $b)) { return $a }
        Start-Sleep -Milliseconds 600
    }
    return $null
}

function Test-Blob([string]$modName, [byte[]]$bytes) {
    # 只接受"看起来完整"的快照：魔数对 + 有记录行
    if ($null -eq $bytes -or $bytes.Length -lt 32) { return $false }
    $magic = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
    if ($modName -match "review" -and $magic -ne "MRV2") { return $false }
    if ($modName -match "rating" -and $magic -ne "IWE1") { return $false }
    if ($modName -match "review") {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text.IndexOf("R|") -lt 0) { return $false }
    }
    return $true
}

function Get-Sha256([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "") }
    finally { $sha.Dispose() }
}

function Write-Bytes([string]$path, [byte[]]$bytes) {
    $tmp = $path + ".tmp"
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    Move-Item -LiteralPath $tmp -Destination $path
}

# ---------------------------------------------------------------- 主体
function Invoke-Backup {
    $dir = Find-IsaacDir
    if (-not $dir) {
        Log "找不到游戏目录，跳过本次"
        return 1
    }

    $sources = @()
    foreach ($modDir in (Get-ChildItem (Join-Path $dir "data") -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match "^highlight-" })) {
        foreach ($f in (Get-ChildItem $modDir.FullName -Filter "*.dat" -ErrorAction SilentlyContinue)) {
            $sources += [pscustomobject]@{ File = $f; Mod = $modDir.Name }
        }
    }
    if ($sources.Count -eq 0) {
        Log "游戏目录下没有 highlight-* 存档，跳过"
        return 1
    }

    $saved = 0; $same = 0; $bad = 0
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $day = Get-Date -Format "yyyyMMdd"

    foreach ($s in $sources) {
        $tag = "{0}_{1}" -f $s.Mod, $s.File.BaseName          # highlight-review_save3
        $bytes = Read-Blob $s.File.FullName
        if ($null -eq $bytes) { Log "$tag 读不到（游戏在写？）"; $bad++; continue }
        if (-not (Test-Blob $s.Mod $bytes)) { Log ("$tag 校验失败（{0} 字节），跳过" -f $bytes.Length); $bad++; continue }

        $hash = Get-Sha256 $bytes
        $latest = Join-Path $LatestDir "$tag.dat"
        if (Test-Path -LiteralPath $latest) {
            $old = [System.IO.File]::ReadAllBytes($latest)
            if ((Get-Sha256 $old) -eq $hash) { $same++; continue }
        }

        Write-Bytes (Join-Path $AutoDir "$tag-$stamp.dat") $bytes
        Write-Bytes $latest $bytes
        $dayFile = Join-Path $DailyDir "$tag-$day.dat"
        if (-not (Test-Path -LiteralPath $dayFile)) { Write-Bytes $dayFile $bytes }
        Log ("{0} 已存 {1:N0} 字节" -f $tag, $bytes.Length)
        $saved++
    }

    # 滚动清理（latest 与 daily 不参与 auto 的计数）
    $auto = Get-ChildItem $AutoDir -Filter "*.dat" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*-latest.dat" } |
            Sort-Object LastWriteTime -Descending
    if ($auto.Count -gt $Keep) {
        $auto | Select-Object -Skip $Keep | ForEach-Object { Remove-Item $_.FullName -Force }
        Log ("auto 清理 {0} 份（保留 {1}）" -f ($auto.Count - $Keep), $Keep)
    }
    $daily = Get-ChildItem $DailyDir -Filter "*.dat" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending
    $dailyBudget = [Math]::Max($KeepDays * $sources.Count, $sources.Count)
    if ($daily.Count -gt $dailyBudget) {
        $daily | Select-Object -Skip $dailyBudget | ForEach-Object { Remove-Item $_.FullName -Force }
        Log ("daily 清理到 {0} 份" -f $dailyBudget)
    }

    # 日志自身限长：约 2000 行，防止十年后变成几 MB
    if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item $LogFile).Length -gt 300KB)) {
        $tail = Get-Content -LiteralPath $LogFile -Tail 2000 -Encoding UTF8
        Set-Content -LiteralPath $LogFile -Value $tail -Encoding UTF8
    }

    if ($saved -eq 0 -and $bad -eq 0) { Log "没有变化（$same 个来源内容未变）" }
    else { Log ("本次：新增 {0}，未变 {1}，失败 {2}" -f $saved, $same, $bad) }
    return 0
}

# ---------------------------------------------------------------- 任务计划
function Install-Task {
    $vbs = Join-Path $PSScriptRoot "backup-saves.vbs"
    if (-not (Test-Path -LiteralPath $vbs)) { Say "缺少 $vbs" Red; return 1 }

    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + $vbs + '"')
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
        -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -Hidden
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Description "以撒 mod 存档快照：每 $EveryMinutes 分钟把 highlight-* 的 .dat 复制到 _logs\save-backup" `
            -Force -ErrorAction Stop | Out-Null
    } catch {
        Say ("注册失败：" + $_.Exception.Message) Red
        Say "如果提示权限不足，用管理员 PowerShell 重跑 -Install" Yellow
        return 1
    }
    Say ("已注册任务 {0}（每 {1} 分钟）" -f $TaskName, $EveryMinutes) Green
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) { Say ("  状态：{0}  下次：{1}" -f $t.State, (Get-ScheduledTaskInfo $TaskName).NextRunTime) }
    return 0
}

function Uninstall-Task {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { Say "任务不存在" Yellow; return 0 }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Say ("已删除任务 {0}" -f $TaskName) Green
    return 0
}

function Show-Status {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        $info = Get-ScheduledTaskInfo $TaskName
        Say ("任务：{0}  状态 {1}" -f $TaskName, $t.State) Green
        Say ("  上次运行 {0}  结果 0x{1:X}  下次 {2}" -f $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime)
    } else {
        Say "任务未安装（用 -Install）" Yellow
    }
    $auto = Get-ChildItem $AutoDir -Filter "*.dat" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    Say ("快照：auto {0} 份 / daily {1} 份 / 合计 {2:N1} MB" -f `
        $auto.Count, (Get-ChildItem $DailyDir -Filter "*.dat" -ErrorAction SilentlyContinue).Count,
        ((($auto | Measure-Object Length -Sum).Sum + (Get-ChildItem $DailyDir -Filter "*.dat" -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB))
    $auto | Select-Object -First 6 | ForEach-Object { Say ("  {0}  {1,10:N0}  {2}" -f $_.LastWriteTime.ToString("MM-dd HH:mm:ss"), $_.Length, $_.Name) }
    if (Test-Path -LiteralPath $LogFile) { Say ("日志：{0}" -f $LogFile) }
    return 0
}

# ---------------------------------------------------------------- 入口
if ($Uninstall) { exit (Uninstall-Task) }
if ($Install)   { exit (Install-Task) }
if ($Status)    { exit (Show-Status) }
exit (Invoke-Backup)
