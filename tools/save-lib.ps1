# =============================================================================
# save-lib.ps1 -- 存档快照的共享逻辑（被 backup-saves.ps1 / save-watch.ps1 共用）
#
# 只做三件事：找来源 -> 读稳定内容 -> 去重落盘/清理。
# 不打印、不调度、不碰 UI —— 那两件事由调用方决定。
# =============================================================================

$script:SaveLibRoot = $null

function Get-IsaacDirSafe {
    try {
        . (Join-Path $PSScriptRoot "_paths.ps1")
        return $IsaacDir
    } catch {
        return $null
    }
}

function Expand-Token([string]$s, [string]$isaacDir) {
    if (-not $s) { return $s }
    $out = $s
    if ($isaacDir) { $out = $out.Replace("%ISAAC%", $isaacDir) }
    return [Environment]::ExpandEnvironmentVariables($out)
}

# ---------------------------------------------------------------- 配置
function Get-DefaultSources {
    return @(
        [pscustomobject]@{
            name = "highlight-review"; path = "%ISAAC%\data\highlight-review\*.dat"
            everyMinutes = 10; keep = 100; keepDays = 60; validator = "mrv2"; enabled = $true
        },
        [pscustomobject]@{
            name = "highlight-rating"; path = "%ISAAC%\data\highlight-rating\*.dat"
            everyMinutes = 10; keep = 100; keepDays = 60; validator = "iwe1"; enabled = $true
        }
    )
}

function Get-Sources([string]$configPath, [string]$isaacDir) {
    if (-not (Test-Path -LiteralPath $configPath)) { return (Get-DefaultSources) }

    try { $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw ("配置文件解析失败：" + $configPath + " —— " + $_.Exception.Message) }

    $def = @{ everyMinutes = 10; keep = 100; keepDays = 60; validator = "auto"; enabled = $true }
    if ($cfg.defaults) {
        foreach ($k in @("everyMinutes", "keep", "keepDays", "validator")) {
            if ($null -ne $cfg.defaults.$k) { $def[$k] = $cfg.defaults.$k }
        }
    }

    $out = @()
    foreach ($s in $cfg.sources) {
        if (-not $s.name -or -not $s.path) { continue }
        $item = [pscustomobject]@{
            name         = [string]$s.name
            path         = Expand-Token ([string]$s.path) $isaacDir
            everyMinutes = if ($null -ne $s.everyMinutes) { [int]$s.everyMinutes } else { [int]$def.everyMinutes }
            keep         = if ($null -ne $s.keep) { [int]$s.keep } else { [int]$def.keep }
            keepDays     = if ($null -ne $s.keepDays) { [int]$s.keepDays } else { [int]$def.keepDays }
            validator    = if ($s.validator) { [string]$s.validator } else { [string]$def.validator }
            enabled      = if ($null -ne $s.enabled) { [bool]$s.enabled } else { $true }
        }
        if ($item.enabled) { $out += $item }
    }
    if ($out.Count -eq 0) { return (Get-DefaultSources) }
    return $out
}

function Resolve-SourceFiles($src) {
    $p = $src.path
    if (-not $p) { return @() }
    $dir = Split-Path $p -Parent
    $leaf = Split-Path $p -Leaf
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Filter $leaf -File -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- 读盘 / 校验
function Read-StableBytes([string]$path) {
    # 游戏写盘时可能读到半截：连读两次一致才认。存档没有结尾换行，没法靠长度判断。
    for ($i = 1; $i -le 4; $i++) {
        $a = $null
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
                if ($read -eq $len) { $a = $buf }
            } finally { $fs.Dispose() }
        } catch { }
        if ($null -eq $a) { Start-Sleep -Milliseconds 600; continue }
        Start-Sleep -Milliseconds 250
        $b = $null
        try {
            $b = [System.IO.File]::ReadAllBytes($path)
        } catch { }
        if ($null -ne $b -and $a.Length -eq $b.Length -and (Get-Sha256 $a) -eq (Get-Sha256 $b)) { return $a }
        Start-Sleep -Milliseconds 600
    }
    return $null
}

function Test-SaveBlob([string]$validator, [byte[]]$bytes) {
    if ($null -eq $bytes -or $bytes.Length -lt 32) { return $false }
    $magic = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
    switch ($validator) {
        "mrv2" { return ($magic -eq "MRV2") }
        "iwe1" { return ($magic -eq "IWE1") }
        "auto" { return ($magic -eq "MRV2" -or $magic -eq "IWE1" -or $magic -match "^[A-Za-z0-9]{4}$") }
        default { return $true }
    }
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

# ---------------------------------------------------------------- 一个来源的一轮
function Invoke-Source($src, [string]$root) {
    $res = [pscustomobject]@{
        Name = $src.name; Total = 0; Saved = 0; Same = 0; Bad = 0; Bytes = 0
        Events = New-Object System.Collections.ArrayList
    }

    $autoDir = Join-Path $root "auto"
    $dailyDir = Join-Path $root "daily"
    $latestDir = Join-Path $root "latest"
    foreach ($d in @($autoDir, $dailyDir, $latestDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    $files = Resolve-SourceFiles $src
    $res.Total = $files.Count
    if ($files.Count -eq 0) {
        [void]$res.Events.Add([pscustomobject]@{ Kind = "warn"; Text = "没找到文件（游戏目录/路径不对？）" })
        return $res
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $day = Get-Date -Format "yyyyMMdd"

    foreach ($f in $files) {
        $tag = "{0}_{1}" -f $src.name, $f.BaseName
        $bytes = Read-StableBytes $f.FullName
        if ($null -eq $bytes) {
            $res.Bad++
            [void]$res.Events.Add([pscustomobject]@{ Kind = "bad"; Text = "$tag 读不到（正在写盘？）" })
            continue
        }
        if (-not (Test-SaveBlob $src.validator $bytes)) {
            $res.Bad++
            [void]$res.Events.Add([pscustomobject]@{ Kind = "bad"; Text = ("$tag 校验失败（{0:N0} B）" -f $bytes.Length) })
            continue
        }

        $hash = Get-Sha256 $bytes
        $latest = Join-Path $latestDir "$tag.dat"
        if (Test-Path -LiteralPath $latest) {
            $old = [System.IO.File]::ReadAllBytes($latest)
            if ((Get-Sha256 $old) -eq $hash) { $res.Same++; continue }
        }

        Write-Bytes (Join-Path $autoDir "$tag-$stamp.dat") $bytes
        Write-Bytes $latest $bytes
        $dayFile = Join-Path $dailyDir "$tag-$day.dat"
        if (-not (Test-Path -LiteralPath $dayFile)) { Write-Bytes $dayFile $bytes }

        $res.Saved++
        $res.Bytes += $bytes.Length
        [void]$res.Events.Add([pscustomobject]@{ Kind = "ok"; Text = ("{0} 已存 {1:N0} B" -f $tag, $bytes.Length) })
    }

    # 滚动清理：只清本来源自己的文件（前缀匹配）
    $prefix = $src.name + "_"
    $auto = @(Get-ChildItem -LiteralPath $autoDir -Filter "$prefix*.dat" -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending)
    if ($auto.Count -gt $src.keep) {
        $n = $auto.Count - $src.keep
        $auto | Select-Object -Skip $src.keep | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        [void]$res.Events.Add([pscustomobject]@{ Kind = "info"; Text = ("清理旧快照 {0} 份（保留 {1}）" -f $n, $src.keep) })
    }
    $daily = @(Get-ChildItem -LiteralPath $dailyDir -Filter "$prefix*.dat" -File -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)
    if ($daily.Count -gt $src.keepDays) {
        $daily | Select-Object -Skip $src.keepDays | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    return $res
}

function Add-BackupLog([string]$root, [string]$text) {
    $logFile = Join-Path $root "backup.log"
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $text
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    if ((Test-Path -LiteralPath $logFile) -and ((Get-Item $logFile).Length -gt 300KB)) {
        $tail = Get-Content -LiteralPath $logFile -Tail 2000 -Encoding UTF8
        Set-Content -LiteralPath $logFile -Value $tail -Encoding UTF8
    }
}
