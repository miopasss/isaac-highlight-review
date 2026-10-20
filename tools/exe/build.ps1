# =============================================================================
# build.ps1 —— 编译 tools\exe\ 下的三个启动器
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\exe\build.ps1
#
# 编译完得到 Book.exe / ParseSave.exe / Rooms.exe，
# 它们会自己向上找到项目根（需要 tests 或 mod 目录存在），
# 所以 exe 放在 tools\exe\ 里也不影响使用。
# =============================================================================
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$here = $PSScriptRoot
$src  = Join-Path $here "src"

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "找不到 csc.exe（需要 .NET Framework 4）" }

$common = Join-Path $src "LauncherCommon.cs"
if (-not (Test-Path $common)) { throw "找不到 $common" }

$targets = @(
    @{ name = "Book";      file = "BookLauncher.cs" },
    @{ name = "ParseSave"; file = "ParseSaveLauncher.cs" },
    @{ name = "Rooms";     file = "RoomsLauncher.cs" }
)

foreach ($t in $targets) {
    $source = Join-Path $src $t.file
    $exePath = Join-Path $here ($t.name + ".exe")
    if (-not (Test-Path $source)) {
        Write-Host ("  ✘ {0}: 找不到 {1}" -f $t.name, $t.file) -ForegroundColor Red
        continue
    }
    & $csc /nologo /target:exe /out:$exePath $source $common 2>&1 | Out-Null
    if (Test-Path $exePath) {
        Write-Host ("  ✔ {0}.exe  {1:N0} B" -f $t.name, (Get-Item $exePath).Length)
    } else {
        Write-Host ("  ✘ {0}.exe 编译失败" -f $t.name) -ForegroundColor Red
    }
}
