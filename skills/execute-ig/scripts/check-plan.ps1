[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [string]$RepoRoot,
    [switch]$AsJson
)

# Deterministic part of the plan-for-cursor passes. Reads one plan and the
# repository it targets; never edits either. Item numbers:
#   1 manifest before the first slice, SHA-base resolves to a commit
#   2 capsule: no abbreviated path (... or the ellipsis character) in backticks, no parent_plan:
#   3 every backend test project the plan cites exists, or is created in a Reuso block
#   4 every slice has a Reuso block and names its discriminante
#   5 the verification table has every mandatory row
# Exit 0 = clean, 1 = at least one BLOCK, 2 = no BLOCK but a check could not run
# or the script failed (UNVERIFIED, item 0 for a failure).
# The judgment parts of the passes (neighbor test, declared error codes, traced
# fixtures) stay in the skill text.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$findings = [Collections.Generic.List[object]]::new()
function Add-Finding([int]$Item, [string]$Severity, [int]$Line, [string]$Message) {
    $findings.Add([pscustomobject]@{ Item = $Item; Severity = $Severity; Line = $Line; Message = $Message })
}
# Non-ASCII written as code points: Windows PowerShell reads a BOM-less script as ANSI.
$requiredRows = @('Manifesto', 'Encanamento', 'Ambiente', 'Testes', 'Projeto do teste', 'Gate', 'Rules', "C$([char]0xE1)psula", 'Cobertura', 'Reuso', "Contradi$([char]0xE7)$([char]0xE3)o", 'Erros declarados')
$testsDir = 'platform/backend/tests'

$previousEncoding = $null
try {
    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (& git rev-parse --show-toplevel) }
    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
    $full = if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $RepoRoot $PlanPath }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Plan not found: $PlanPath" }
    $lines = @(([IO.File]::ReadAllText($full, [Text.Encoding]::UTF8) -replace "`r`n", "`n").Split("`n"))
    # A "#" line inside a fenced code block (shell or YAML comment) is not a heading.
    $fenced = [bool[]]::new($lines.Count)
    $inFence = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*(```|~~~)') { $fenced[$i] = $true; $inFence = -not $inFence; continue }
        $fenced[$i] = $inFence
    }
    function Get-HeadingLevel([int]$Index) {
        if (-not $fenced[$Index] -and $lines[$Index] -match '^(#{1,6})\s') { return $Matches[1].Length }
        0
    }
    function Find-Line([string]$Pattern, [int]$From = 0) {
        for ($i = $From; $i -lt $lines.Count; $i++) { if (-not $fenced[$i] -and $lines[$i] -match $Pattern) { return $i } }
        -1
    }

    # Slices: "## Fatia N" .. "#### Fatia N"; each runs to the next heading of the same or higher level.
    $slices = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $fenced[$i] -and $lines[$i] -match '^(#{2,4})\s+Fatia\b') {
            $level = $Matches[1].Length
            $end = $lines.Count
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $h = Get-HeadingLevel $j
                if ($h -and $h -le $level) { $end = $j; break }
            }
            $slices += [pscustomobject]@{ Start = $i; End = $end; Title = $lines[$i].Trim() }
        }
    }

    # Item 1 - manifest.
    $manifest = Find-Line "^#{2,3}\s+Manifesto de execu$([char]0xE7)$([char]0xE3)o"
    if ($manifest -lt 0) {
        Add-Finding 1 'BLOCK' 0 'No "## Manifesto de execucao" section (plan-for-cursor, manifest section).'
    } else {
        if ($slices.Count -and $manifest -gt $slices[0].Start) {
            Add-Finding 1 'BLOCK' ($manifest + 1) "The manifest comes after the first slice ($($slices[0].Title)); it must precede every slice."
        }
        $manifestEnd = $lines.Count
        for ($j = $manifest + 1; $j -lt $lines.Count; $j++) { $h = Get-HeadingLevel $j; if ($h -and $h -le 3) { $manifestEnd = $j; break } }
        $sha = $null; $shaLine = 0
        for ($j = $manifest; $j -lt $manifestEnd; $j++) {
            if ($lines[$j] -match 'SHA-base' -and $lines[$j] -match '`([0-9a-f]{7,40})`') { $sha = $Matches[1]; $shaLine = $j + 1; break }
        }
        if (-not $sha) {
            Add-Finding 1 'BLOCK' ($manifest + 1) 'The manifest has no SHA-base in backticks.'
        } else {
            $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & git -C $RepoRoot cat-file -e "$sha^{commit}" 2>$null; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $previous }
            if ($code -ne 0) { Add-Finding 1 'BLOCK' $shaLine "SHA-base $sha is not a commit in $RepoRoot." }
        }
    }

    # Item 2 - capsule.
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in [regex]::Matches($lines[$i], '`([^`]+)`')) {
            $token = $m.Groups[1].Value
            if ($token -match '/' -and $token -match "\.\.\.|$([char]0x2026)") {
                Add-Finding 2 'BLOCK' ($i + 1) "Abbreviated path ``$token``; write it in full from the repository root (pass 10a)."
            }
        }
        if ($lines[$i] -match '^\s*parent_plan\s*:') {
            Add-Finding 2 'BLOCK' ($i + 1) 'parent_plan: points to a larger document; copy the fact instead (pass 10b).'
        }
    }

    # Item 3 - test projects. A project that does not exist yet passes only when a Reuso row
    # names it with the decision to create it; a bare name inside another path is not a backend project.
    $reuseRows = [Collections.Generic.List[string]]::new()
    $inReuse = $false
    foreach ($l in $lines) {
        if ($l -match '\*\*Reuso:\*\*') { $inReuse = $true; continue }
        if ($inReuse) {
            if ($l -match '^\s*\|') { $reuseRows.Add($l) }
            elseif (-not [string]::IsNullOrWhiteSpace($l)) { $inReuse = $false }
        }
    }
    $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $names = @()
        foreach ($m in [regex]::Matches($lines[$i], [regex]::Escape($testsDir) + '/([A-Za-z0-9_.-]+)')) { $names += $m.Groups[1].Value }
        foreach ($m in [regex]::Matches($lines[$i], '(?<![/\\\w.-])(Insurtech\.[A-Za-z0-9.]+\.Tests)\b')) { $names += $m.Groups[1].Value }
        foreach ($name in $names) {
            if ($seen.ContainsKey($name)) { continue }
            $seen[$name] = $true
            if (Test-Path -LiteralPath (Join-Path $RepoRoot "$testsDir/$name") -PathType Container) { continue }
            if (@($reuseRows | Where-Object { $_ -like "*$name*" -and $_ -match '(?i)\bcriar\b' }).Count) { continue }
            Add-Finding 3 'BLOCK' ($i + 1) "Test project $name does not exist under $testsDir. Use the project of the neighbor test, or declare its creation in the slice's Reuso block (pass 4g)."
        }
    }

    # Item 4 - slices.
    if (-not $slices.Count) {
        Add-Finding 4 'UNVERIFIED' 0 'No "### Fatia" heading found; the Reuso and discriminante checks did not run.'
    }
    foreach ($s in $slices) {
        $body = $lines[$s.Start..($s.End - 1)] -join "`n"
        if ($body -notmatch '\*\*Reuso:\*\*') {
            Add-Finding 4 'BLOCK' ($s.Start + 1) "$($s.Title): no **Reuso:** block (pass 12)."
        }
        if ($body -notmatch '(?i)discriminante') {
            Add-Finding 4 'BLOCK' ($s.Start + 1) "$($s.Title): names no discriminante, nor says it has none (pass 4e)."
        }
    }

    # Item 5 - verification table.
    $table = Find-Line "^#{1,3}\s+Verifica$([char]0xE7)$([char]0xF5)es feitas antes de entregar este plano"
    if ($table -lt 0) {
        Add-Finding 5 'BLOCK' 0 'No "Verificacoes feitas antes de entregar este plano" section.'
    } else {
        $cells = @()
        for ($j = $table + 1; $j -lt $lines.Count; $j++) {
            $h = Get-HeadingLevel $j
            if ($h -and $h -le 3) { break }
            if ($lines[$j] -match '^\s*\|([^|]*)\|') { $cells += ($Matches[1] -replace '\*', '').Trim() }
        }
        foreach ($row in $requiredRows) {
            if (-not @($cells | Where-Object { $_ -like "$row*" }).Count) {
                Add-Finding 5 'BLOCK' ($table + 1) "Verification table has no ""$row"" row; if the pass does not apply, keep the row and say why."
            }
        }
    }
} catch {
    # A crash never reads as clean or as a plan defect.
    Add-Finding 0 'UNVERIFIED' 0 "The check itself failed: $($_.Exception.Message)"
} finally { if ($previousEncoding) { [Console]::OutputEncoding = $previousEncoding } }

$exit = if (@($findings | Where-Object Severity -eq 'BLOCK').Count) { 1 } elseif (@($findings | Where-Object Severity -eq 'UNVERIFIED').Count) { 2 } else { 0 }
$status = @('CLEAN', 'BLOCKED', 'UNVERIFIED')[$exit]
if ($AsJson) {
    [pscustomobject]@{ Status = $status; Plan = $PlanPath; Findings = @($findings) } | ConvertTo-Json -Depth 4 -Compress
} else {
    foreach ($f in $findings) {
        $where = if ($f.Line) { " ${PlanPath}:$($f.Line)" } else { " $PlanPath" }
        Write-Output "$($f.Severity) [item $($f.Item)]$where - $($f.Message)"
    }
    Write-Output "Plan check: $status ($PlanPath)"
}
exit $exit
