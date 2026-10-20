# =============================================================================
# build.ps1 —— 编译 tools\exe\ 下的三个启动器
# 用法：.\tools\exe\build.ps1
# =============================================================================
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$out  = $here
$src  = Join-Path $here "src"

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "找不到 csc.exe" }

$common = Join-Path $src "LauncherCommon.cs"
$targets = @(
    @{ name = "Book";      file = "BookLauncher.cs" },
    @{ name = "ParseSave"; file = "ParseSaveLauncher.cs" },
    @{ name = "Rooms";     file = "RoomsLauncher.cs" }
)

foreach ($t in $targets) {
    $exePath = Join-Path $out ($t.name + ".exe")
    & $csc /nologo /target:exe /out:$exePath (Join-Path $src $t.file) $common 2>&1 | Out-Null
    if (Test-Path $exePath) {
        Write-Host ("  ✔ {0}.exe  {1:N0} B" -f $t.name, (Get-Item $exePath).Length)
    } else {
        Write-Host ("  ✘ {0}.exe 编译失败" -f $t.name) -ForegroundColor Red
    }
}