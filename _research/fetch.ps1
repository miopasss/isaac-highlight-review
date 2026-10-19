param([string[]]$Urls, [string]$Base, [string]$OutDir, [string]$Prefix = '')

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($name in $Urls) {
    $url = if ($name -match '^https?://') { $name } else { "$Base$name" }
    $raw = Join-Path $env:TEMP 'raw_page.html'
    $code = curl.exe -sS --ssl-no-revoke -m 40 -o $raw $url 2>&1
    if (-not (Test-Path $raw)) { Write-Output "FAIL(no file) $url"; continue }
    $h = Get-Content $raw -Raw
    if (-not $h) { Write-Output "FAIL(empty) $url"; continue }
    $h2 = [regex]::Replace($h, '(?is)<script.*?</script>', '')
    $h2 = [regex]::Replace($h2, '(?is)<style.*?</style>', '')
    # remember code blocks as markers so we can keep them
    $t = [regex]::Replace($h2, '(?s)<[^>]+>', "`n")
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $lines = $t -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $slug = ($name -replace '^https?://', '' -replace '[^\w\.-]', '_')
    $out = Join-Path $OutDir "$Prefix$slug.txt"
    $lines -join "`n" | Out-File -Encoding utf8 $out
    Write-Output "OK $url  lines=$($lines.Count)  -> $out"
    Remove-Item $raw -Force -ErrorAction SilentlyContinue
}
