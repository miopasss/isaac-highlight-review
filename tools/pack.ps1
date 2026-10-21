# =============================================================================
# pack.ps1 —— 打包成可直接上传创意工坊的压缩包
#
# 用法：
#   powershell -File tools\pack.ps1                 # 两个都打
#   powershell -File tools\pack.ps1 -Mod rating
#   powershell -File tools\pack.ps1 -Mod review
#
# 产物：dist\highlight-rating.zip / dist\highlight-review.zip
#
# 只打包该 mod 目录本身（README.md 会带进去，不影响游戏加载）。
# 绝不带 tools\ tests\ shared\ docs\ _logs\ _backup\ 这些东西。
# =============================================================================
param(
    [ValidateSet("both", "review", "rating")]
    [string]$Mod = "both"
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path $PSScriptRoot -Parent
$Dist = Join-Path $Root "dist"

# 先保证 shared\ 已经复制进各 mod（否则打出来的包缺 settings.lua）
& (Join-Path $PSScriptRoot "deploy.ps1") -Mod $Mod 2>&1 | Out-Null

if (-not (Test-Path $Dist)) { New-Item -ItemType Directory -Path $Dist | Out-Null }

$targets = @()
if ($Mod -in @("both", "review")) { $targets += @{ Src = "mod-review"; Zip = "highlight-review" } }
if ($Mod -in @("both", "rating")) { $targets += @{ Src = "mod-rating"; Zip = "highlight-rating" } }

Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($t in $targets) {
    $src = Join-Path $Root $t.Src
    $zip = Join-Path $Dist ($t.Zip + ".zip")
    if (-not (Test-Path $src)) { Write-Host ("  ✘ 缺少目录 {0}" -f $src) -ForegroundColor Red; continue }

    if (Test-Path $zip) { Remove-Item $zip -Force }

    # 压缩包内顶层目录名 = metadata 里的 directory
    $archive = [System.IO.Compression.ZipFile]::Open($zip, "Create")
    try {
        $files = Get-ChildItem -Path $src -Recurse -File
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($src.Length).TrimStart('\')
            $entryName = ($t.Zip + "/" + ($rel -replace '\\', '/'))
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $f.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        }
        Write-Host ("  ✔ {0}  {1} 个文件  {2:N0} B" -f (Split-Path $zip -Leaf), $files.Count, (Get-Item $zip).Length)
    } finally {
        $archive.Dispose()
    }
}

Write-Host ""
Write-Host ("产物在 {0}" -f $Dist)
