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
    [int]$MeasureSec = 10
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot\..\tools\_paths.ps1"
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
    # ---- 0) keep the old log
    if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 0)) {
        $dst = Join-Path $OutRoot ("{0}-previous-log.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        Copy-Item $Log $dst -Force
        Say "  old log saved: $dst" DarkGray
    }

    # ---- 1) close any running instance first
    Close-Game | Out-Null

    # ---- 2) apply disable.it
    foreach ($m in $Disable) {
        $dir = Join-Path $Mods $m
        if (-not (Test-Path $dir)) { Say "  !! mod folder not found: $m" Red; continue }
        $f = Join-Path $dir "disable.it"
        if (-not (Test-Path $f)) {
            Set-Content -Path $f -Value "" -NoNewline
            [void]$created.Add($f)
            Say "  disabled: $m" DarkGray
        }
    }
    Say ("  enabled mods this round: " + (@(Get-ChildItem $Mods -Directory | Where-Object { -not (Test-Path (Join-Path $_.FullName 'disable.it')) }).Count)) Green

    # ---- 3) launch
    $t0 = Get-Date
    Launch-Game

    # ---- 4) wait for the flood
    $firstAssertAt = $null
    $sawHighlight = $false
    while (((Get-Date) - $t0).TotalSeconds -lt $WaitSec) {
        Start-Sleep -Seconds 2
        $txt = Read-LogText
        if ($txt.Length -eq 0) { continue }
        if (-not $sawHighlight -and $txt.Contains("[HIGHLIGHT] loaded")) { $sawHighlight = $true }
        if ($txt.Contains("[ASSERT] - PushRenderTarget")) {
            $firstAssertAt = (Get-Date) - $t0
            break
        }
        if ($sawHighlight -and ((Get-Date) - $t0).TotalSeconds -gt 130) { break }
    }

    if ($firstAssertAt) {
        $result.flood = "yes"
        $result.seconds_to_first_assert = [math]::Round($firstAssertAt.TotalSeconds, 1)
        Say ("  FLOOD starts at {0:N1}s after launch" -f $firstAssertAt.TotalSeconds) Yellow
        Start-Sleep -Seconds 3
        $c1 = ([regex]::Matches((Read-LogText), '\[ASSERT\] - PushRenderTarget')).Count
        $ts = Get-Date
        Start-Sleep -Seconds $MeasureSec
        $t2 = Read-LogText
        $c2 = ([regex]::Matches($t2, '\[ASSERT\] - PushRenderTarget')).Count
        $dt = ((Get-Date) - $ts).TotalSeconds
        $result.asserts = $c2
        $result.rate = [math]::Round(($c2 - $c1) / $dt, 1)
        $result.log_bytes = (Get-Item $Log).Length
        Say ("  asserts total={0}  rate={1}/s  log={2} bytes" -f $c2, $result.rate, $result.log_bytes) Yellow
    } else {
        $result.flood = "no"
        $txt = Read-LogText
        $result.asserts = ([regex]::Matches($txt, '\[ASSERT\] - PushRenderTarget')).Count
        $result.log_bytes = (Get-Item $Log).Length
        $result.note = ("waited {0}s, highlight_loaded={1}, log={2}B" -f $WaitSec, $sawHighlight, $result.log_bytes)
        Say ("  no flood after {0}s (highlight_loaded={1}, log={2}B)" -f $WaitSec, $sawHighlight, $result.log_bytes) Green
    }
}
finally {
    # ---- 5) close game, restore disable.it
    Close-Game | Out-Null
    foreach ($f in $created) {
        if (Test-Path $f) { Remove-Item $f -Force }
    }
    if ($created.Count -gt 0) { Say ("  restored {0} disable.it" -f $created.Count) DarkGray }
    $line = ($result | ConvertTo-Json -Compress)
    Say ""
    Say ("== RESULT " + $line) Cyan
    Add-Content -Path (Join-Path $OutRoot "bisect-results.jsonl") -Value $line
}
