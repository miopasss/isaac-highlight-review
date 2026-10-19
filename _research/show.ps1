param([string]$File, [switch]$Body, [switch]$Toc)
$l = Get-Content $File
$cls = $l | Select-String -Pattern '^Class "' | Select-Object -First 1
$onThis = $l | Select-String -Pattern '^On this page$' | Select-Object -First 1
if ($Toc -and $onThis) {
    $end = if ($cls) { $cls.LineNumber - 2 } else { $l.Count - 1 }
    Write-Output "--- TOC ($($onThis.LineNumber+1)..$end) ---"
    $l[($onThis.LineNumber)..$end] | ForEach-Object { $_ }
}
if ($Body) {
    if ($cls) {
        Write-Output "--- BODY from $($cls.LineNumber) ---"
        $l[($cls.LineNumber-1)..($l.Count-1)] | ForEach-Object { $_ }
    } else { Write-Output "!! no Class marker in $File" }
}
if (-not $Toc -and -not $Body) { Write-Output "count=$($l.Count) classAt=$($cls.LineNumber) onThisPageAt=$($onThis.LineNumber)" }
