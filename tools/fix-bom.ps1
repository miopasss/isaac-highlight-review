# fix-bom.ps1 - re-save every .ps1 in tools/ as UTF-8 WITH BOM.
# Windows PowerShell 5.1 reads BOM-less .ps1 as GBK and chokes on Chinese comments,
# so any script that was edited by a tool which strips the BOM must be re-saved here.
# This file itself is pure ASCII on purpose (it has to run before the fix).

$fixed = 0
Get-ChildItem $PSScriptRoot -Filter *.ps1 | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host ("ok    " + $_.Name)
        return
    }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    [System.IO.File]::WriteAllText($_.FullName, $text, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host ("fixed " + $_.Name)
    $script:fixed++
}
Write-Host ("done, fixed {0} file(s)" -f $fixed)
