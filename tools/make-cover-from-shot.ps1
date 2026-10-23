# =============================================================================
# make-cover-from-shot.ps1 —— 用真实界面截图做创意工坊封面
#
# 输入：docs\img\src-editor-panel.png（一张真实的编辑器窗口截图）
# 输出：docs\img\workshop-cover.png  512×512   （工坊预览图）
#       docs\img\workshop-wide.png  1280×720   （页面内大图）
#
# 做法：深色底 + 标题 + 把截图裁掉旧窗口标题栏后缩放进画面 + 底部说明。
# 之所以要裁标题栏：源图标题写的是 "Highlight Review · 道具评级"，
# 那是拆分前的旧名字，和这个 mod（Item Weight Editor）对不上。
# =============================================================================
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Add-Type -AssemblyName System.Drawing

$Root   = Split-Path $PSScriptRoot -Parent
$ImgDir = Join-Path $Root "docs\img"
$Shot   = Join-Path $ImgDir "src-editor-panel.png"

if (-not (Test-Path $Shot)) { throw "找不到 $Shot" }

$srcImg = [System.Drawing.Image]::FromFile($Shot)

# 裁掉顶部窗口标题栏（源图高 532，标题栏约 34px）
$cropTop = 34
$cropH = $srcImg.Height - $cropTop
$cropRect = New-Object System.Drawing.Rectangle(0, $cropTop, $srcImg.Width, $cropH)

function New-Cover([int]$W, [int]$H, [string]$Path, [double]$Scale) {
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # 背景
    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.ColorTranslator]::FromHtml("#101018"),
        [System.Drawing.ColorTranslator]::FromHtml("#232331"),
        90.0)
    $g.FillRectangle($bg, $rect)

    # 顶条
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#4a6fa5"))
    $g.FillRectangle($accent, 0, 0, $W, [int](6 * $Scale))

    # 标题
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $dim   = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#c2c2d0"))
    $faint = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#7d7d8c"))

    $fTitle = New-Object System.Drawing.Font("Segoe UI", [float](32 * $Scale), [System.Drawing.FontStyle]::Bold)
    $fSub   = New-Object System.Drawing.Font("Microsoft YaHei", [float](17 * $Scale), [System.Drawing.FontStyle]::Regular)
    $fFoot  = New-Object System.Drawing.Font("Segoe UI", [float](10 * $Scale), [System.Drawing.FontStyle]::Regular)
    $fHint  = New-Object System.Drawing.Font("Consolas", [float](10 * $Scale), [System.Drawing.FontStyle]::Regular)

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center

    $g.DrawString("Item Weight Editor", $fTitle, $white,
        (New-Object System.Drawing.RectangleF(0, (18 * $Scale), $W, (44 * $Scale))), $sf)
    $g.DrawString("道具权重编辑器", $fSub, $dim,
        (New-Object System.Drawing.RectangleF(0, (58 * $Scale), $W, (28 * $Scale))), $sf)

    # 截图区（等比缩放，居中）
    $marginX = [int]($W * 0.05)
    $top     = [int](96 * $Scale)          # 标题块高度（随尺寸缩放）
    $maxW    = $W - 2 * $marginX
    $maxH    = [int]($H - $top - $H * 0.18) # 底部留 18% 给说明和出处

    $ratio = [Math]::Min($maxW / $srcImg.Width, $maxH / $cropH)
    $dw = [int]($srcImg.Width * $ratio)
    $dh = [int]($cropH * $ratio)
    $dx = [int](($W - $dw) / 2)
    $dy = $top

    # 边框 + 阴影感
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#3a3a4c"), [float](2 * $Scale))
    $dstRect = New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)
    $g.DrawImage($srcImg, $dstRect, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawRectangle($borderPen, $dstRect)

    # 底部：权重说明 + 出处
    $hintY = $dy + $dh + [int](10 * $Scale)
    $g.DrawString("0 = never      0.5 = half      1 = unchanged", $fHint, $faint,
        (New-Object System.Drawing.RectangleF(0, $hintY, $W, (16 * $Scale))), $sf)
    $g.DrawString("The Binding of Isaac: Repentance  -  requires REPENTOGON", $fFoot, $faint,
        (New-Object System.Drawing.RectangleF(0, ($H - 24 * $Scale), $W, (16 * $Scale))), $sf)

    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host ("  ✔ {0}  {1}x{2}  {3:N0} B" -f (Split-Path $Path -Leaf), $W, $H, (Get-Item $Path).Length)
}

New-Cover -W 512  -H 512 -Path (Join-Path $ImgDir "workshop-cover.png") -Scale 1.0
New-Cover -W 1280 -H 720 -Path (Join-Path $ImgDir "workshop-wide.png")  -Scale 2.0

$srcImg.Dispose()
Write-Host ""
Write-Host "产物：docs\img\workshop-cover.png（512×512）" -ForegroundColor Cyan
