[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [string]$MessageFile,
    [string]$Commit,
    [string]$RepoRoot,
    [switch]$AsJson
)

# Deterministic check of a slice commit message (execute-ig step 4). Run it on the
# draft message before `git commit` (-MessageFile) and again on the commit (-Commit).
# Reads the message and the plan; never edits either. Item numbers:
#   1 the three trailers (Execute-Plan, Execute-Base, Execute-Slice)
#   2 the "Afirmacoes:" section exists ("Afirmacoes: nenhuma" counts) and every line in it has "prova:"
#   3 the plan's elected discriminant of the slice has a "[visto]" on the line that names it
#   4 no gap marker outside the exempt lines ("Decisao D<n>:" lines and the "Fatias pendentes:" section)
# Exit 0 = clean, 1 = at least one BLOCK, 2 = the message or the plan could not be read
# or the script failed (UNVERIFIED, item 0).
# -MessageFile always checks: the draft is a slice commit by intent. -Commit <sha> skips a
# commit that carries no Execute-* trailer at all (the step 6 fix commits); a commit that
# carries some trailer but not all three is a violation.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$findings = [Collections.Generic.List[object]]::new()
function Add-Finding([int]$Item, [string]$Severity, [int]$Line, [string]$Message) {
    $findings.Add([pscustomobject]@{ Item = $Item; Severity = $Severity; Line = $Line; Message = $Message })
}
# Non-ASCII written as code points: Windows PowerShell reads a BOM-less script as ANSI.
$cao = "$([char]0xE7)$([char]0xE3)o"; $coes = "$([char]0xE7)$([char]0xF5)es"
$dec = "Decis$([char]0xE3)o"
$notImpl = "n$([char]0xE3)o implementad"
$gapMarkers = @(
    '\blacuna', '\bpendente', 'fica para', "\b$notImpl", '\bnao implementad', '\bknown gap', '\bdeferred',
    '\bfollow-up', '\bfor later', '\bout of scope', '\bknown limitation'
)
$source = 'message'

$previousEncoding = $null
try {
    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (& git rev-parse --show-toplevel) }
    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
    if ([bool]$MessageFile -eq [bool]$Commit) { throw 'Pass exactly one of -MessageFile or -Commit.' }

    if ($MessageFile) {
        if (-not (Test-Path -LiteralPath $MessageFile -PathType Leaf)) { throw "Message file not found: $MessageFile" }
        $text = [IO.File]::ReadAllText($MessageFile, [Text.Encoding]::UTF8)
    } else {
        $source = "commit $Commit"
        $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $text = (& git -C $RepoRoot log -1 --format=%B $Commit 2>&1 | ForEach-Object { "$_" }) -join "`n"; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $previous }
        if ($code -ne 0) { throw "Cannot read $source`: $text" }
    }
    $msg = @(($text -replace "`r`n", "`n").Split("`n"))

    $planFull = if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $RepoRoot $PlanPath }
    if (-not (Test-Path -LiteralPath $planFull -PathType Leaf)) { throw "Plan not found: $PlanPath" }
    $plan = @(([IO.File]::ReadAllText($planFull, [Text.Encoding]::UTF8) -replace "`r`n", "`n").Split("`n"))

    # Trailers.
    $trailers = @{}
    for ($i = 0; $i -lt $msg.Count; $i++) {
        if ($msg[$i] -match '^(Execute-(?:Plan|Base|Slice)):\s*(\S.*?)\s*$') { $trailers[$Matches[1]] = $Matches[2] }
    }
    if ($Commit -and $trailers.Count -eq 0) {
        # Not a slice commit (step 6 fix commit): out of scope.
        $findings.Clear()
    } else {
        foreach ($key in 'Execute-Plan', 'Execute-Base', 'Execute-Slice') {
            if (-not $trailers.ContainsKey($key)) { Add-Finding 1 'BLOCK' 0 "Missing trailer ${key}: (step 4 commit body)." }
        }

        # Sections and exempt lines.
        $isTrailer = { param($l) $l -match '^Execute-(?:Plan|Base|Slice):' }
        $isHeader = { param($l) $l -match '^[^\s\-*][^:]{0,60}:\s*$' }
        $claimsStart = -1; $claimsInline = $false
        for ($i = 0; $i -lt $msg.Count; $i++) {
            if ($msg[$i] -match "^\s*Afirma${coes}\s*:") {
                $claimsStart = $i; $claimsInline = ($msg[$i] -match ':\s*\S'); break
            }
        }
        $claimLines = @{}
        if ($claimsStart -lt 0) {
            Add-Finding 2 'BLOCK' 0 "No ""Afirma${coes}:"" section; write ""Afirma${coes}: nenhuma"" when the body states no behavior."
        } else {
            $claimLines[$claimsStart] = $true
            if (-not $claimsInline) {
                $count = 0
                for ($j = $claimsStart + 1; $j -lt $msg.Count; $j++) {
                    $l = $msg[$j]
                    if ([string]::IsNullOrWhiteSpace($l) -or (& $isTrailer $l) -or (& $isHeader $l)) { break }
                    $claimLines[$j] = $true; $count++
                    if ($l -notmatch '(?i)\bprova\s*:') { Add-Finding 2 'BLOCK' ($j + 1) "Claim without ""prova:"" (test, grep or command): $($l.Trim())" }
                }
                if (-not $count) { Add-Finding 2 'BLOCK' ($claimsStart + 1) "Empty ""Afirma${coes}:"" section; write ""Afirma${coes}: nenhuma"" or list the claims." }
            }
        }

        # Exempt lines for the gap markers.
        $exempt = @{}
        for ($i = 0; $i -lt $msg.Count; $i++) {
            if ($msg[$i] -match "^\s*[-*]?\s*${dec} D\d+\s*:") { $exempt[$i] = $true }
            if ($msg[$i] -match '^\s*Fatias pendentes\s*:') {
                $exempt[$i] = $true
                for ($j = $i + 1; $j -lt $msg.Count; $j++) {
                    $l = $msg[$j]
                    if ([string]::IsNullOrWhiteSpace($l) -or (& $isTrailer $l) -or (& $isHeader $l)) { break }
                    $exempt[$j] = $true
                }
            }
        }
        for ($i = 0; $i -lt $msg.Count; $i++) {
            if ($exempt.ContainsKey($i) -or (& $isTrailer $msg[$i])) { continue }
            $hit = $null
            foreach ($marker in $gapMarkers) { if ($msg[$i] -match "(?i)$marker") { $hit = $Matches[0]; break } }
            # TODO is case-sensitive: in Portuguese "todo" is an ordinary word.
            if (-not $hit -and $msg[$i] -cmatch '\bTODO\b') { $hit = 'TODO' }
            if ($hit) { Add-Finding 4 'BLOCK' ($i + 1) "Gap marker ""$hit"" outside an exempt line (a slice is not approved with a declared gap; make it a ""${dec} D<n>:"" line or a required test): $($msg[$i].Trim())" }
        }

        # Elected discriminant.
        if ($trailers.ContainsKey('Execute-Slice')) {
            $id = ($trailers['Execute-Slice'] -replace '(?i)^\s*fatia\s+', '' -replace '(?i)^S(?=\d)', '').Trim()
            # Real trailers carry the frontmatter todo id (e.g. f6-modulo-smoke) while the heading is "### F6 - ...":
            # also try the todo's own "B1:" label and the id's first segment.
            $candidates = @($id)
            $rawId = ($trailers['Execute-Slice'] -replace '(?i)^\s*fatia\s+', '').Trim()
            if ($rawId -ne $id) { $candidates += $rawId }
            $idx = -1
            for ($k = 0; $k -lt $plan.Count; $k++) { if ($plan[$k] -match ('^\s*-\s*id:\s*"?' + [regex]::Escape($id) + '"?\s*$')) { $idx = $k; break } }
            if ($idx -ge 0) {
                if ($idx + 1 -lt $plan.Count -and $plan[$idx + 1] -match '^\s*content:\s*"?\s*([^:"]{1,20}):') { $candidates += $Matches[1].Trim() }
                if ($id -match '^([A-Za-z]+\d+)-') { $candidates += $Matches[1] }
            }
            $start = -1; $end = $plan.Count; $level = 0; $inFence = $false
            for ($i = 0; $i -lt $plan.Count; $i++) {
                if ($plan[$i] -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
                if ($inFence) { continue }
                if ($start -lt 0) {
                    if ($plan[$i] -match '^(#{2,4})\s+(.*)$') {
                        $title = $Matches[2]; $lvl = $Matches[1].Length
                        foreach ($cand in $candidates) {
                            if ($title -match "(?i)^\s*(?:fatia\s+)?$([regex]::Escape($cand))(?![\w.])" -or $title -match "(?i)\bfatia\s+$([regex]::Escape($cand))(?![\w.])") { $start = $i; $level = $lvl; break }
                        }
                    }
                } elseif ($plan[$i] -match '^(#{1,6})\s') {
                    if ($Matches[1].Length -le $level) { $end = $i; break }
                }
            }
            if ($start -lt 0) {
                Add-Finding 0 'UNVERIFIED' 0 "Slice ""$id"" has no heading in $PlanPath; the discriminant check did not run."
            } else {
                $tests = @()
                for ($i = $start; $i -lt $end; $i++) {
                    if ($plan[$i] -match '(?i)discriminante da fatia[:*\s]*`([^`]+)`') { $tests += $Matches[1].Trim() }
                }
                foreach ($t in $tests) {
                    $seen = @($msg | Where-Object { $_.Contains($t) -and $_ -match '\[visto\]' }).Count
                    if (-not $seen) { Add-Finding 3 'BLOCK' 0 "No ""[visto]"" on a line that names the slice's elected discriminant ``$t`` (plan-for-cursor pass 4e)." }
                }
            }
        }
    }
} catch {
    # A crash never reads as clean or as a commit defect.
    $findings.Clear()
    Add-Finding 0 'UNVERIFIED' 0 "The check itself failed: $($_.Exception.Message)"
} finally { if ($previousEncoding) { [Console]::OutputEncoding = $previousEncoding } }

$exit = if (@($findings | Where-Object Severity -eq 'BLOCK').Count) { 1 } elseif (@($findings | Where-Object Severity -eq 'UNVERIFIED').Count) { 2 } else { 0 }
$status = @('CLEAN', 'BLOCKED', 'UNVERIFIED')[$exit]
if ($AsJson) {
    [pscustomobject]@{ Status = $status; Source = $source; Findings = @($findings) } | ConvertTo-Json -Depth 4 -Compress
} else {
    foreach ($f in $findings) {
        $where = if ($f.Line) { " line $($f.Line)" } else { '' }
        Write-Output "$($f.Severity) [item $($f.Item)]$where - $($f.Message)"
    }
    Write-Output "Slice commit check: $status ($source)"
}
exit $exit
