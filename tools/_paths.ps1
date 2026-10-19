# =============================================================================
# _paths.ps1 —— 自动定位游戏目录（不要在其他脚本里硬编码路径）
#
# 用法：在脚本开头 dot-source 它
#   . "$PSScriptRoot\_paths.ps1"
#   # 之后 $IsaacDir 就是游戏根目录
#
# 定位顺序：
#   1. 环境变量 ISAAC_DIR（最高优先级，方便多套安装/测试）
#   2. Steam 注册表指向的安装目录
#   3. steamapps/libraryfolders.vdf 里列出的所有库
#   4. 常见默认路径
# 找到的判定标准：目录下存在 isaac-ng.exe
# =============================================================================

function Resolve-IsaacDir {
    $exeName = "isaac-ng.exe"
    $sub = "steamapps\common\The Binding of Isaac Rebirth"

    # 1) 环境变量
    if ($env:ISAAC_DIR) {
        if (Test-Path (Join-Path $env:ISAAC_DIR $exeName)) { return (Resolve-Path $env:ISAAC_DIR).Path }
    }

    # 2) 注册表
    $steamRoots = @()
    foreach ($k in @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )) {
        if (Test-Path $k) {
            $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
            foreach ($v in @($p.SteamPath, $p.InstallPath)) {
                if ($v -and (Test-Path $v)) { $steamRoots += ($v -replace '/', '\') }
            }
        }
    }

    # 3) 常见默认路径
    foreach ($v in @("$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam")) {
        if ($v -and (Test-Path $v)) { $steamRoots += $v }
    }

    # 4) 展开 libraryfolders.vdf 里登记的库
    $libs = @()
    foreach ($r in ($steamRoots | Select-Object -Unique)) {
        $libs += $r
        $vdf = Join-Path $r "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            try {
                $text = Get-Content $vdf -Raw -ErrorAction Stop
                foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                    $libs += $m.Groups[1].Value.Replace('\\', '\')
                }
            } catch { }
        }
    }

    foreach ($lib in ($libs | Select-Object -Unique)) {
        $cand = Join-Path $lib $sub
        if (Test-Path (Join-Path $cand $exeName)) { return (Resolve-Path $cand).Path }
    }

    return $null
}

$IsaacDir = Resolve-IsaacDir

if (-not $IsaacDir) {
    Write-Host ""
    Write-Host "找不到《以撒的结合》安装目录。" -ForegroundColor Red
    Write-Host ""
    Write-Host "解决办法（任选其一）：" -ForegroundColor Yellow
    Write-Host "  A. 设一个环境变量指向游戏根目录："
    Write-Host '     $env:ISAAC_DIR = "X:\Steam\steamapps\common\The Binding of Isaac Rebirth"'
    Write-Host "  B. 确认 Steam 已安装且游戏在某个 Steam 库中"
    Write-Host "  C. 手动改 tools\_paths.ps1，在 Resolve-IsaacDir 里加一条候选路径"
    Write-Host ""
    throw "找不到游戏目录"
}

# 项目根目录（tools/ 的上一级）
$ProjectRoot = Split-Path $PSScriptRoot -Parent
