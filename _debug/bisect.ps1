# =============================================================================
# bisect.ps1 -- one round of the "who fills the render target stack" bisect.
#
# Usage (ASCII only on purpose, PS 5.1 safe):
#   powershell -NoProfile -ExecutionPolicy Bypass -File _debug\bisect.ps1 -Tag r1 [-Disable "a","b"]
#
# What it does:
#   1. copies the old log aside
#   2. creates disable.it inside the given mod folders (nothing else is touched)
#   3. launches the game through steam -applaunch
#   4. watches log.txt for "[ASSERT] - PushRenderTarget"
#   5. reports FLOOD yes/no + asserts per second
#   6. closes the game and removes the disable.it files it created
# =============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string[]]$Disable = @(),
    [int]$WaitSec = 200,
    [int]$MeasureSec = 10,
    [switch]$EnterRun,
    [int]$HoldSec = 0
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot\..\tools\_paths.ps1"
. "$PSScriptRoot\..\tools\_win.ps1"
$Game = $IsaacDir
$Mods = Join-Path $Game "mods"
$LogDir = Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance"
$Log = Join-Path $LogDir "log.txt"
$OutRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "_logs\bisect"
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

function Say($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }

function Close-Game([int]$timeoutSec = 20) {
    $p = Get-Process isaac-ng -ErrorAction SilentlyContinue
    if (-not $p) { return $true }
    Say "  closing isaac-ng (pid $($p.Id)) ..." DarkGray
    $p.CloseMainWindow() | Out-Null
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline -and (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 400
    }
    $p2 = Get-Process isaac-ng -ErrorAction SilentlyContinue
    if ($p2) { Say "  force kill" Yellow; Stop-Process -Id $p2.Id -Force; Start-Sleep -Seconds 2 }
    return $true
}

function Launch-Game {
    $steamExe = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamExe -ErrorAction SilentlyContinue).SteamExe
    if ($steamExe -and (Test-Path ($steamExe -replace '/', '\'))) {
        $steamExe = $steamExe -replace '/', '\'
        Say "  steam.exe -applaunch 250900 ..." DarkGray
        Start-Process -FilePath $steamExe -ArgumentList "-applaunch 250900" -WorkingDirectory (Split-Path $steamExe -Parent)
    } else {
        Say "  steam.exe not found, direct launch" Yellow
        Start-Process -FilePath (Join-Path $Game "isaac-ng.exe") -WorkingDirectory $Game
    }
}

function Read-LogText {
    if (-not (Test-Path $Log)) { return "" }
    try {
        $fs = [System.IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object System.IO.StreamReader($fs)
        $t = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
        return $t
    } catch { return "" }
}

function Focus-Game {
    $w = Get-GameWindow
    if (-not $w -or $w.Handle -eq [IntPtr]::Zero) { return $false }
    if (-not (Focus-Window $w)) { Start-Sleep -Milliseconds 300; return (Focus-Window $w) }
    return $true
}

function Press-Key([string]$key) {
    if (-not (Focus-Game)) { Say ("  !! no game window for key " + $key) Red; return $false }
    Send-GameKey $key
    Start-Sleep -Milliseconds 600
    return $true
}

function Shot-Name([string]$name) {
    $w = Get-GameWindow
    if (-not $w) { return }
    $p = Join-Path $OutRoot ("{0}-{1}.png" -f $Tag, $name)
    try { Save-WindowShot $w $p } catch { Say "  shot failed: $($_)" Yellow }
}

function Enter-The-Run {
    # title -> file select -> slot menu -> continue. Success = a room actually gets set up.
    for ($i = 1; $i -le 5; $i++) {
        Press-Key "ENTER" | Out-Null
        for ($k = 0; $k -lt 6; $k++) {
            Start-Sleep -Seconds 1
            $t = Read-LogText
            if ($t -match 'Room \d+\.\d+\(' -or $t -match 'ChangeRoom' -or $t -match '\[HIGHLIGHT\] F\d') {
                Say ("  entered the run after {0} Enter(s)" -f $i) Green
                return $true
            }
        }
        Shot-Name ("press{0}" -f $i)
    }
    Say "  !! never reached a room" Red
    return $false
}

$created = New-Object System.Collections.ArrayList
$result = [ordered]@{
    tag = $Tag
    disabled = ($Disable -join ";")
    flood = "unknown"
    asserts = 0
    rate = 0
    seconds_to_first_assert = 0
    log_bytes = 0
    note = ""
}

try {
    # ---- 0) keep the old log, then remove it so every round starts from a fresh file
    if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 0)) {
        $dst = Join-Path $OutRoot ("{0}-{1}-previous-log.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $Tag)
        Copy-Item $Log $dst -Force
        Say ("  old log saved ({0} bytes): {1}" -f (Get-Item $Log).Length, $dst) DarkGray
    }
    if (Test-Path $Log) { Remove-Item $Log -Force -ErrorAction SilentlyContinue }
    if (Test-Path $Log) { Say "  !! could not remove old log" Red }

    # ---- 1) close any running instance first
    Close-Game | Out-Null
    if (Test-Path $Log) { Remove-Item $Log -Force -ErrorAction SilentlyContinue }

    # ---- 2) apply disable.it
    $Disable = @($Disable | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($m in $Disable) {
        $dir = Join-Path $Mods $m
        if (-not (Test-Path -LiteralPath $dir)) { Say "  !! mod folder not found: $m" Red; continue }
        $f = Join-Path $dir "disable.it"
        if (-not (Test-Path -LiteralPath $f)) {
            Set-Content -LiteralPath $f -Value "" -NoNewline
            [void]$created.Add($f)
            Say "  disabled: $m" DarkGray
        }
    }
    Say ("  enabled mods this round: " + (@(Get-ChildItem $Mods -Directory | Where-Object { -not (Test-Path (Join-Path $_.FullName 'disable.it')) }).Count)) Green

    # ---- 3) launch
    $t0 = Get-Date
    Launch-Game

    # ---- 3.5) wait for mods to load, optionally enter the run
    $entered = $false
    if ($EnterRun) {
        $deadline = (Get-Date).AddSeconds(180)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            $t = Read-LogText
            if ($t -match '\[HIGHLIGHT\] loaded') { break }
        }
        Say ("  mods loaded at {0:N0}s" -f ((Get-Date) - $t0).TotalSeconds) DarkGray
        Start-Sleep -Seconds 3
        Shot-Name "00-menu"
        $entered = Enter-The-Run
        $result.note = "entered_run=$entered"
        Start-Sleep -Seconds 3
        Shot-Name "01-run"
        $t0 = (Get-Date).AddSeconds(-0.5)   # 杩涘眬閭ｄ竴鍒诲綋浣滄柊涓€杞娴嬭捣鐐?        Start-Sleep -Seconds 4
    }

    # ---- 4) watch the log for the assert flood
    $firstAssertAt = $null
    $highlightAt = $null
    $lastSize = 0
    $watchLimit = if ($EnterRun) { 50 } else { $WaitSec }
    $watchFrom = Get-Date
    while (((Get-Date) - $watchFrom).TotalSeconds -lt $watchLimit) {
        Start-Sleep -Seconds 2
        if (-not (Test-Path $Log)) { continue }
        $sz = (Get-Item $Log).Length
        if ($sz -eq $lastSize -and $sz -lt 4096) { continue }
        $lastSize = $sz
        $txt = Read-LogText
        if ($txt.Length -eq 0) { continue }
        if (-not $highlightAt -and $txt.Contains("[HIGHLIGHT] loaded")) { $highlightAt = Get-Date }
        if ($txt.Contains("[ASSERT] - PushRenderTarget")) {
            $firstAssertAt = (Get-Date) - $watchFrom
            break
        }
        # 鏈繘灞€鏃讹細鍔犺浇瀹屾垚鍚庡啀瑙傚療 45 绉掍粛鏃犳柇瑷€灏卞垽"娌℃湁娲按"
        if (-not $EnterRun -and $highlightAt -and ((Get-Date) - $highlightAt).TotalSeconds -gt 45) { break }
    }

    if ($firstAssertAt) {
        $result.flood = "yes"
        $result.seconds_to_first_assert = [math]::Round($firstAssertAt.TotalSeconds, 1)
        Say ("  FLOOD detected ({0:N1}s into the watch window)" -f $firstAssertAt.TotalSeconds) Yellow
        Start-Sleep -Seconds 3
        $c1 = ([regex]::Matches((Read-LogText), '\[ASSERT\] - PushRenderTarget')).Count
        $ts = Get-Date
        Start-Sleep -Seconds $MeasureSec
        $t2 = Read-LogText
        $c2 = ([regex]::Matches($t2, '\[ASSERT\] - PushRenderTarget')).Count
        $dt = ((Get-Date) - $ts).TotalSeconds
        $result.asserts = $c2
        if ($dt -gt 0.5) { $result.rate = [math]::Round(($c2 - $c1) / $dt, 1) }
        $result.log_bytes = (Get-Item $Log).Length
        Say ("  asserts total={0}  rate={1}/s  log={2} bytes" -f $c2, $result.rate, $result.log_bytes) Yellow
        if ($HoldSec -gt 0) { Say ("  holding {0}s for external probing ..." -f $HoldSec) Cyan; Start-Sleep -Seconds $HoldSec }
    } else {
        $result.flood = "no"
        $txt = Read-LogText
        $result.asserts = ([regex]::Matches($txt, '\[ASSERT\] - PushRenderTarget')).Count
        $result.log_bytes = (Get-Item $Log).Length
        $result.note = ("{0}; entered_run={1}, highlight_loaded={2}, log={3}B" -f $result.note, $entered, ([bool]$highlightAt), $result.log_bytes)
        Say ("  no flood (entered={0}, highlight_loaded={1}, log={2}B)" -f $entered, ([bool]$highlightAt), $result.log_bytes) Green
    }
}
finally {
    # ---- 5) close game, restore disable.it
    Close-Game | Out-Null
    try {
        if (Test-Path $Log) { Copy-Item $Log (Join-Path $OutRoot ("{0}-log.txt" -f $Tag)) -Force }
    } catch { }
    foreach ($f in $created) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
    if ($created.Count -gt 0) { Say ("  restored {0} disable.it" -f $created.Count) DarkGray }
    $line = ($result | ConvertTo-Json -Compress)
    Say ""
    Say ("== RESULT " + $line) Cyan
    Add-Content -Path (Join-Path $OutRoot "bisect-results.jsonl") -Value $line
}



