# =============================================================================
# make-cover.ps1 —— 生成创意工坊封面图
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-cover.ps1
#
# 产物：
#   docs\img\workshop-cover.png    512×512   （创意工坊预览图）
#   docs\img\workshop-wide.png    1280×720   （页面内大图 / 介绍用）
#
# 风格照 mod 自己的 ImGui 面板：深色底 + 蓝色标题栏 + 道具行。
# 字体用微软雅黑（中英都能显示）。
# =============================================================================
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Add-Type -AssemblyName System.Drawing

$Root = Split-Path $PSScriptRoot -Parent
$OutDir = Join-Path $Root "docs\img"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$Rows = @(
    @{ Id = "118";  Name = "Brimstone";        Tag = "Weight 0.00"; TagColor = "#e06060" },
    @{ Id = "1166"; Name = "Exchange Ticket";  Tag = "Rating 4.00"; TagColor = "#6fb0e0" },
    @{ Id = "1";    Name = "The Sad Onion";    Tag = "Weight 0.50"; TagColor = "#e0b060" },
    @{ Id = "33";   Name = "The Bible";        Tag = "Disabled";    TagColor = "#8a8a96" }
)

function New-Cover([int]$W, [int]$H, [string]$Path, [double]$Scale) {

    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # ── 背景：深色渐变 ───────────────────────────────────────────────────
    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.ColorTranslator]::FromHtml("#12121a"),
        [System.Drawing.ColorTranslator]::FromHtml("#232331"),
        90.0)
    $g.FillRectangle($bg, $rect)

    # 顶部强调条
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#4a6fa5"))
    $g.FillRectangle($accent, 0, 0, $W, [int](6 * $Scale))

    # ── 标题 ────────────────────────────────────────────────────────────
    $fTitle = New-Object System.Drawing.Font("Segoe UI", [float](34 * $Scale), [System.Drawing.FontStyle]::Bold)
    $fSub   = New-Object System.Drawing.Font("Microsoft YaHei", [float](20 * $Scale), [System.Drawing.FontStyle]::Regular)
    $fRow   = New-Object System.Drawing.Font("Consolas", [float](13 * $Scale), [System.Drawing.FontStyle]::Regular)
    $fFoot  = New-Object System.Drawing.Font("Segoe UI", [float](10.5 * $Scale), [System.Drawing.FontStyle]::Regular)

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $dim   = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#b9b9c6"))
    $faint = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#7d7d8c"))

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center

    $g.DrawString("Item Weight Editor", $fTitle, $white,
        (New-Object System.Drawing.RectangleF(0, (22 * $Scale), $W, (50 * $Scale))), $sf)
    $g.DrawString("道具权重编辑器", $fSub, $dim,
        (New-Object System.Drawing.RectangleF(0, (74 * $Scale), $W, (34 * $Scale))), $sf)

    # ── 模拟面板 ────────────────────────────────────────────────────────
    $px = [int](36 * $Scale)
    $py = [int](118 * $Scale)
    $pw = $W - 2 * $px
    $ph = [int](($H - $py) - 70 * $Scale)

    $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#1b1b26"))
    $panelPen   = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#3a3a4c"), [float](1 * $Scale))
    $g.FillRectangle($panelBrush, $px, $py, $pw, $ph)
    $g.DrawRectangle($panelPen, $px, $py, $pw, $ph)

    # 面板标题栏
    $barBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#2f4f7a"))
    $g.FillRectangle($barBrush, $px + 1, $py + 1, $pw - 2, [int](24 * $Scale))
    $fBar = New-Object System.Drawing.Font("Segoe UI", [float](11 * $Scale), [System.Drawing.FontStyle]::Bold)
    $g.DrawString("Item Weight Editor", $fBar, $white, [float]($px + 8 * $Scale), [float]($py + 5 * $Scale))

    # 行
    $rowY = $py + [int](34 * $Scale)
    foreach ($r in $Rows) {
        $bar = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#26263400"))
        $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#22222e"))),
            $px + 1, $rowY, $pw - 2, [int](26 * $Scale))

        $txt = "{0,-5} {1}" -f $r.Id, $r.Name
        $g.DrawString($txt, $fRow, $dim, [float]($px + 10 * $Scale), [float]($rowY + 6 * $Scale))

        $fTag = New-Object System.Drawing.Font("Consolas", [float](12 * $Scale), [System.Drawing.FontStyle]::Bold)
        $tagBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($r.TagColor))
        $tagSize = $g.MeasureString($r.Tag, $fTag)
        $g.DrawString($r.Tag, $fTag, $tagBrush,
            [float]($px + $pw - 14 * $Scale - $tagSize.Width), [float]($rowY + 6 * $Scale))

        $rowY += [int](30 * $Scale)
        if ($rowY -gt ($py + $ph - 40 * $Scale)) { break }
    }

    # 面板内的说明
    $fHint = New-Object System.Drawing.Font("Consolas", [float](10 * $Scale), [System.Drawing.FontStyle]::Regular)
    $g.DrawString("0 = never      0.5 = half      1 = unchanged", $fHint, $faint,
        [float]($px + 10 * $Scale), [float]($py + $ph - 26 * $Scale))

    # ── 底部 ────────────────────────────────────────────────────────────
    $g.DrawString("The Binding of Isaac: Repentance", $fFoot, $faint,
        (New-Object System.Drawing.RectangleF(0, ($H - 46 * $Scale), $W, (18 * $Scale))), $sf)
    $g.DrawString("requires REPENTOGON", $fFoot, $faint,
        (New-Object System.Drawing.RectangleF(0, ($H - 30 * $Scale), $W, (18 * $Scale))), $sf)

    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host ("  ✔ {0}  {1}x{2}  {3:N0} B" -f (Split-Path $Path -Leaf), $W, $H, (Get-Item $Path).Length)
}

New-Cover -W 512  -H 512 -Path (Join-Path $OutDir "workshop-cover.png") -Scale 1.0
New-Cover -W 1280 -H 720 -Path (Join-Path $OutDir "workshop-wide.png")  -Scale 2.0
Write-Host ""
Write-Host "产物：docs\img\workshop-cover.png（512×512，创意工坊预览图）" -ForegroundColor Cyan
