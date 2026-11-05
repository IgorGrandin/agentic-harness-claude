[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [string]$Slice,
    [string]$RepoRoot
)

# Prints only what a resumed /execute-ig session needs from a plan, so the whole plan is never read.
#   without -Slice: the slice headings, with line numbers and sizes (to pick the pending one)
#   with -Slice <id>: the manifest section, the "Decisoes" section, the slice section, and every
#                     table row of the plan that mentions the slice id (coverage matrix rows)
# <id> is the heading id: "S4", "Fatia 4", "4" or the frontmatter todo id. Read-only; exit 2 when not found.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (& git rev-parse --show-toplevel) }
    $full = if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $RepoRoot $PlanPath }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Plan not found: $PlanPath" }
    $lines = @(([IO.File]::ReadAllText($full, [Text.Encoding]::UTF8) -replace "`r`n", "`n").Split("`n"))
    $fenced = [bool[]]::new($lines.Count)
    $inFence = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*(```|~~~)') { $fenced[$i] = $true; $inFence = -not $inFence; continue }
        $fenced[$i] = $inFence
    }
    function Get-Level([int]$i) { if (-not $fenced[$i] -and $lines[$i] -match '^(#{1,6})\s') { return $Matches[1].Length }; 0 }
    function Get-End([int]$start) {
        $level = Get-Level $start
        for ($j = $start + 1; $j -lt $lines.Count; $j++) { $h = Get-Level $j; if ($h -and $h -le $level) { return $j } }
        $lines.Count
    }
    function Write-Block([int]$start, [int]$end) {
        Write-Output "--- $([IO.Path]::GetFileName($full)) lines $($start + 1)-$end ---"
        $lines[$start..($end - 1)] | ForEach-Object { Write-Output $_ }
    }

    $sliceHeads = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $level = Get-Level $i
        if ($level -ge 2 -and $level -le 4 -and $lines[$i] -match '^#{2,4}\s+(Fatia\b|S\d+\b)') { $sliceHeads += $i }
    }
    if (-not $Slice) {
        foreach ($i in $sliceHeads) { Write-Output ("{0,5}  {1}  ({2} lines)" -f ($i + 1), $lines[$i].Trim(), ((Get-End $i) - $i)) }
        exit 0
    }

    $esc = [regex]::Escape($Slice)
    $target = -1
    foreach ($i in $sliceHeads) {
        if ($lines[$i] -match "^#{2,4}\s+(Fatia\s+)?$esc\b" -or $lines[$i] -match "^#{2,4}\s+Fatia\s+(?:[A-Za-z]+[\s-]+)?$esc\b") { $target = $i; break }
    }
    if ($target -lt 0) { [Console]::Error.WriteLine("Slice '$Slice' not found; run without -Slice to list them."); exit 2 }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ne $target -and (Get-Level $i) -ge 2 -and (Get-Level $i) -le 3 -and $lines[$i] -match '^#{2,3}\s+(Manifesto de execu|Decis)') { Write-Block $i (Get-End $i) }
    }
    Write-Block $target (Get-End $target)
    $rows = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ge $target -and $i -lt (Get-End $target)) { continue }
        if (-not $fenced[$i] -and $lines[$i] -match '^\s*\|' -and $lines[$i] -match "(?<![\w])$esc(?![\w])") { $rows += "{0,5}: {1}" -f ($i + 1), $lines[$i] }
    }
    if ($rows.Count) { Write-Output '--- table rows that mention the slice ---'; $rows | ForEach-Object { Write-Output $_ } }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
