# =============================================================================
# make-cover-review.ps1 —— 高光回顾的创意工坊封面
#
# 输入：docs\img\src-book-panel.png（真实册子截图，1562x827）
# 输出：docs\img\workshop-cover-review.png  512x512
#       docs\img\workshop-wide-review.png  1280x720
#
# 和 make-cover-from-shot.ps1 的区别：那一版是给权重编辑器用的（裁旧标题栏），
# 这一版直接用册子截图，标题换成 Highlight Review / 高光回顾。
# =============================================================================
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Add-Type -AssemblyName System.Drawing

$Root   = Split-Path $PSScriptRoot -Parent
$ImgDir = Join-Path $Root "docs\img"
$Shot   = Join-Path $ImgDir "src-book-panel.png"
if (-not (Test-Path $Shot)) { throw "找不到 $Shot" }

$srcImg = [System.Drawing.Image]::FromFile($Shot)
$cropRect = New-Object System.Drawing.Rectangle(0, 0, $srcImg.Width, $srcImg.Height)

function New-Cover([int]$W, [int]$H, [string]$Path, [double]$Scale) {
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # 背景：纸色调 + 渐变（跟册子里的米黄纸呼应）
    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.ColorTranslator]::FromHtml("#2a2118"),
        [System.Drawing.ColorTranslator]::FromHtml("#1a1410"),
        90.0)
    $g.FillRectangle($bg, $rect)

    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#c9a227"))
    $g.FillRectangle($accent, 0, 0, $W, [int](6 * $Scale))

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $cream = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#e8dcc0"))
    $faint = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#9a8f7a"))

    $fTitle = New-Object System.Drawing.Font("Segoe UI", [float](30 * $Scale), [System.Drawing.FontStyle]::Bold)
    $fSub   = New-Object System.Drawing.Font("Microsoft YaHei", [float](16 * $Scale), [System.Drawing.FontStyle]::Regular)
    $fFoot  = New-Object System.Drawing.Font("Segoe UI", [float](10 * $Scale), [System.Drawing.FontStyle]::Regular)

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center

    $g.DrawString("Highlight Review", $fTitle, $white,
        (New-Object System.Drawing.RectangleF(0, (18 * $Scale), $W, (42 * $Scale))), $sf)
    $g.DrawString("高光回顾 · 每局一本战力笔记", $fSub, $cream,
        (New-Object System.Drawing.RectangleF(0, (56 * $Scale), $W, (26 * $Scale))), $sf)

    # 截图：保持比例放进中段
    $marginX = [int]($W * 0.04)
    $top     = [int](92 * $Scale)
    $maxW    = $W - 2 * $marginX
    $maxH    = [int]($H - $top - $H * 0.16)
    $ratio   = [Math]::Min($maxW / $srcImg.Width, $maxH / $srcImg.Height)
    $dw = [int]($srcImg.Width * $ratio)
    $dh = [int]($srcImg.Height * $ratio)
    $dx = [int](($W - $dw) / 2)
    $dy = $top

    $dst = New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)
    $g.DrawImage($srcImg, $dst, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#c9a227"), [float](2 * $Scale))
    $g.DrawRectangle($pen, $dst)

    $g.DrawString("F5 打开 · 总览 / 战力跃迁 / 楼层详情 / 终极Boss", $fFoot, $faint,
        (New-Object System.Drawing.RectangleF(0, ($dy + $dh + 8 * $Scale), $W, (16 * $Scale))), $sf)
    $g.DrawString("The Binding of Isaac: Repentance  -  requires REPENTOGON", $fFoot, $faint,
        (New-Object System.Drawing.RectangleF(0, ($H - 24 * $Scale), $W, (16 * $Scale))), $sf)

    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host ("  ✔ {0}  {1}x{2}  {3:N0} B" -f (Split-Path $Path -Leaf), $W, $H, (Get-Item $Path).Length)
}

New-Cover -W 512  -H 512 -Path (Join-Path $ImgDir "workshop-cover-review.png") -Scale 1.0
New-Cover -W 1280 -H 720 -Path (Join-Path $ImgDir "workshop-wide-review.png")  -Scale 2.0

$srcImg.Dispose()
Write-Host ""
Write-Host "产物：docs\img\workshop-cover-review.png（512×512）" -ForegroundColor Cyan
