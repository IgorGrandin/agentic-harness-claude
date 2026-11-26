[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Base = 'origin/master',
    [int]$GatePipelineId = 158,
    [int]$PrNumber,
    [string]$GateRunsJson,
    [string]$GateTimelineJson,
    [string]$PrWorkItemsJson,
    [string]$AzOrg = 'https://dev.azure.com/confitecDevOps',
    [string]$AzProject = 'brixbroker',
    [switch]$NoFetch,
    [switch]$AsJson
)

# Deterministic part of the owner's recurring blockers list (references/owner-blockers.md).
# Compares the working tree (tracked and untracked) with merge-base(Base, HEAD).
# Item numbers match the list. Exit 0 = clean, 1 = at least one BLOCK,
# 2 = no BLOCK but a check could not run or the script failed (UNVERIFIED, item 0
# for a failure). WARN never changes the exit. Item 10's PR gate part (pipeline 158)
# only ever WARNs: the gate runs after this check, so it cannot make the exit 2.
# -GateRunsJson and -GateTimelineJson replace the Azure DevOps queries (test seam) for the
# PR gate (pipeline 158) runs and the timeline of its newest run; -PrWorkItemsJson replaces the
# query of the work items linked to the PR (item 39).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (& git rev-parse --show-toplevel) }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$findings = [Collections.Generic.List[object]]::new()
function Add-Finding([int]$Item, [string]$Severity, [string]$Path, [int]$Line, [string]$Message) {
    $findings.Add([pscustomobject]@{ Item = $Item; Severity = $Severity; Path = $Path; Line = $Line; Message = $Message })
}
function Invoke-Git([string[]]$GitArgs, [switch]$AllowFail) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & git -C $RepoRoot -c core.quotepath=false @GitArgs 2>$null; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0 -and -not $AllowFail) { throw "git $($GitArgs -join ' ') failed with exit $code" }
    [pscustomobject]@{ Code = $code; Lines = @($out | ForEach-Object { [string]$_ }) }
}
function Normalize([string]$Text) { ($Text -replace "`r`n", "`n").TrimEnd() }
function Get-BaseText([string]$Rev, [string]$Path) {
    $r = Invoke-Git @('show', "${Rev}:$Path") -AllowFail
    if ($r.Code -ne 0) { return $null }
    $r.Lines -join "`n"
}
function Get-CurrentText([string]$Path) {
    $full = Join-Path $RepoRoot $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    [IO.File]::ReadAllText($full, [Text.Encoding]::UTF8)
}
function Test-JustifiedDeep([string[]]$Lines) {
    for ($k = 0; $k -lt $Lines.Count; $k++) {
        if ($Lines[$k] -notmatch '::ng-deep') { continue }
        if ($Lines[$k] -match '//|/\*') { return $true }
        $j = $k - 1
        while ($j -ge 0 -and ([string]::IsNullOrWhiteSpace($Lines[$j]) -or $Lines[$j].TrimEnd().EndsWith(','))) { $j-- }
        if ($j -ge 0 -and ($Lines[$j].Trim() -match '^(//|/\*)' -or $Lines[$j].Trim() -match '\*/$')) { return $true }
    }
    $false
}
function Get-AzJson([string[]]$AzArgs) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & az @AzArgs -o json 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($raw -join "`n") | ConvertFrom-Json
    } catch { return $null }
    finally { $ErrorActionPreference = $previous }
}
function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

$migrationPattern = '(^|/)Migrations/.+\.cs$'
$snapshotPattern = 'ModelSnapshot\.cs$'
$designerPattern = '\.Designer\.cs$'
$generatedApiPattern = '/generated/[^/]+\.types\.ts$'
$sharedPattern = '^platform/frontend/(libs/(design-system|layout|core)/|apps/[^/]+/src/styles[^/]*\.scss$)'
$featureHtmlPattern = '^platform/frontend/libs/(features|[^/]+/features)/.+\.html$'

$previousEncoding = $null; $mb = $null
try { $previousEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { $previousEncoding = $null }
try {
    # Item 10 - the branch contains the current Base. Only warns: Base moves often
    # (doc commits), and merging it on every run is the dev's call.
    $baseFresh = $true
    if (-not $NoFetch -and $Base -match '^([^/]+)/(.+)$') {
        if ((Invoke-Git @('fetch', '--quiet', $Matches[1], $Matches[2]) -AllowFail).Code -ne 0) {
            $baseFresh = $false
            Add-Finding 10 'UNVERIFIED' '' 0 "Could not fetch $Base; the comparison base may be stale."
        }
    }
    if ((Invoke-Git @('rev-parse', '--verify', '--quiet', "$Base^{commit}") -AllowFail).Code -ne 0) { throw "Base '$Base' does not resolve to a commit." }
    $ancestor = (Invoke-Git @('merge-base', '--is-ancestor', $Base, 'HEAD') -AllowFail).Code
    if ($ancestor -eq 1 -and $baseFresh) {
        $behind = (Invoke-Git @('rev-list', '--count', "HEAD..$Base")).Lines[0]
        Add-Finding 10 'WARN' '' 0 "HEAD is $behind commit(s) behind $Base. Merge it and let CI run again before review."
        # Dry run of the merge (git >= 2.38): conflicts are listed before the dev finds them in the PR.
        $mt = Invoke-Git @('merge-tree', '--write-tree', '--name-only', '--no-messages', 'HEAD', $Base) -AllowFail
        if ($mt.Code -eq 1) {
            $conflicted = @($mt.Lines | Select-Object -Skip 1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            $hint = if (@($conflicted | Where-Object { $_ -match 'migrations\.lock$' }).Count) { ' migrations.lock: keep every line from both sides (the architecture test compares the set, not the order).' } else { '' }
            Add-Finding 10 'WARN' '' 0 "Merging $Base into HEAD conflicts in: $($conflicted -join ', ').$hint"
        }
        elseif ($mt.Code -gt 1) { Add-Finding 10 'UNVERIFIED' '' 0 "git merge-tree could not simulate the merge with $Base (exit $($mt.Code))." }
    }
    elseif ($ancestor -gt 1) { throw "git merge-base --is-ancestor failed with exit $ancestor" }
    $mb = (Invoke-Git @('merge-base', $Base, 'HEAD')).Lines[0]

    # Changed files: tracked against the merge-base, plus untracked as added.
    $changes = [Collections.Generic.List[object]]::new()
    foreach ($line in (Invoke-Git @('diff', '--name-status', '--no-color', '--no-ext-diff', '-M', $mb)).Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t"
        $status = $parts[0].Substring(0, 1)
        if ($status -eq 'R' -or $status -eq 'C') { $changes.Add([pscustomobject]@{ Status = $status; Old = $parts[1]; Path = $parts[2] }) }
        else { $changes.Add([pscustomobject]@{ Status = $status; Old = $parts[1]; Path = $parts[1] }) }
    }
    foreach ($path in (Invoke-Git @('ls-files', '--others', '--exclude-standard')).Lines) {
        if (-not [string]::IsNullOrWhiteSpace($path)) { $changes.Add([pscustomobject]@{ Status = 'A'; Old = $null; Path = $path }) }
    }

    # Added lines per file, with their line numbers in the current file.
    $added = @{}
    $current = $null; $next = 0; $inHeader = $false
    foreach ($line in (Invoke-Git @('diff', '-U0', '--no-color', '--no-ext-diff', '-M', $mb)).Lines) {
        if ($line.StartsWith('diff --git ')) { $inHeader = $true; $current = $null; continue }
        $hunk = [regex]::Match($line, '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@')
        if ($hunk.Success) { $inHeader = $false; $next = [int]$hunk.Groups[1].Value; continue }
        if ($inHeader) {
            # git appends a TAB to header paths that contain spaces.
            if ($line.StartsWith('+++ ')) {
                $header = $line.Substring(4).TrimEnd("`t")
                $current = if ($header -eq '/dev/null') { $null } else { $header.Substring(2) }
                if ($current -and -not $added.ContainsKey($current)) { $added[$current] = [Collections.Generic.List[object]]::new() }
            }
            continue
        }
        if ($current -and $line.StartsWith('+')) { $added[$current].Add([pscustomobject]@{ Line = $next; Text = $line.Substring(1) }); $next++ }
    }
    foreach ($c in $changes | Where-Object { $_.Status -eq 'A' -and -not $added.ContainsKey($_.Path) }) {
        $text = Get-CurrentText $c.Path
        if ($null -eq $text) { continue }
        $list = [Collections.Generic.List[object]]::new(); $n = 1
        foreach ($t in ($text -replace "`r`n", "`n") -split "`n") { $list.Add([pscustomobject]@{ Line = $n; Text = $t }); $n++ }
        $added[$c.Path] = $list
    }
    function Get-Added([string]$Path) { if ($added.ContainsKey($Path)) { $added[$Path] } else { @() } }

    # Item 1 - no test that exists at the merge-base disappears.
    $attr = '\[(?:[^\[\]]|\[[^\]]*\])*\]'
    $csTest = '\[(?:Fact|Theory)\b(?:[^\[\]]|\[[^\]]*\])*\](?:\s*' + $attr + ')*\s*public\s+(?:static\s+)?(?:async\s+)?[\w<>\[\],\.\?]+\s+(\w+)\s*\('
    $tsTest = '\b(?:it|test)\s*\(\s*([''"`])(.+?)\1'
    function Get-TestNames([string]$Path, [string]$Text) {
        if ($null -eq $Text) { return @() }
        if ($Path -match '\.cs$') { @([regex]::Matches($Text, $csTest) | ForEach-Object { $_.Groups[1].Value }) }
        else { @([regex]::Matches($Text, $tsTest) | ForEach-Object { $_.Groups[2].Value }) }
    }
    $isTest = { param($p) $p -match '^platform/backend/tests/.+\.cs$' -or $p -match '\.spec\.ts$' }
    # A removal named in a plan changed by this diff, or a whole test file deleted, only warns.
    $planText = (@($changes | Where-Object { $_.Status -ne 'D' -and $_.Path -match '^\.cursor/plans/.+\.md$' } | ForEach-Object { Get-CurrentText $_.Path }) -join "`n")
    # Counted by name across all changed test files: a test moved between files is not a removal,
    # and a duplicate name elsewhere does not hide one.
    $before = [hashtable]::new([StringComparer]::Ordinal); $after = [hashtable]::new([StringComparer]::Ordinal); $origin = [hashtable]::new([StringComparer]::Ordinal)
    foreach ($c in $changes) {
        if ($c.Old -and (& $isTest $c.Old) -and $c.Status -ne 'A') {
            foreach ($name in Get-TestNames $c.Old (Get-BaseText $mb $c.Old)) {
                $before[$name] = 1 + $(if ($before.ContainsKey($name)) { $before[$name] } else { 0 })
                if (-not $origin.ContainsKey($name) -or $c.Status -ne 'D') { $origin[$name] = $c }
            }
        }
        if ($c.Status -ne 'D' -and (& $isTest $c.Path)) {
            foreach ($name in Get-TestNames $c.Path (Get-CurrentText $c.Path)) { $after[$name] = 1 + $(if ($after.ContainsKey($name)) { $after[$name] } else { 0 }) }
        }
    }
    foreach ($name in $before.Keys | Sort-Object) {
        $missing = $before[$name] - $(if ($after.ContainsKey($name)) { $after[$name] } else { 0 })
        if ($missing -le 0) { continue }
        $c = $origin[$name]
        $label = if ($missing -gt 1) { "$missing tests named '$name'" } else { "Test '$name'" }
        if ([regex]::IsMatch($planText, '(?<!\w)' + [regex]::Escape($name) + '(?!\w)')) { Add-Finding 1 'WARN' $c.Old 0 "$label removed; the removal is named in the plan." }
        elseif ($c.Status -eq 'D') { Add-Finding 1 'WARN' $c.Old 0 "$label removed with its whole file. Confirm the behavior it covered was removed too." }
        else { Add-Finding 1 'BLOCK' $c.Old 0 "$label existed at the merge-base and is gone. Restore it and add new tests beside it, or name the removal in the plan." }
    }

    # An ADR this branch renames or deletes frees its number: a slug fix is not a collision.
    $freedAdrs = @($changes | Where-Object { $_.Status -ne 'M' -and $_.Old -and $_.Old -ne $_.Path } | ForEach-Object Old) + @($changes | Where-Object { $_.Status -eq 'D' } | ForEach-Object { $_.Old; $_.Path })
    $baseAdrs = @(@((Invoke-Git @('ls-tree', '--name-only', $Base, 'docs/adr/') -AllowFail).Lines) | Where-Object { $_ -and $freedAdrs -notcontains $_ })
    foreach ($c in $changes) {
        $p = $c.Path
        # Item 2 - shared frontend libs and global styles.
        if ($c.Status -ne 'D' -and $p -match $sharedPattern -and $p -notmatch '\.spec\.ts$' -and $p -notmatch '/generated/') {
            Add-Finding 2 'WARN' $p 0 'Shared library or global style changed in a feature PR. Justify it or move it to its own WI.'
        }
        # Item 3 - generated API types keep the generator header.
        if ($c.Status -ne 'D' -and $p -match $generatedApiPattern) {
            $text = Get-CurrentText $p
            if ($null -ne $text -and $text -notmatch 'auto-generated by openapi-typescript') {
                Add-Finding 3 'BLOCK' $p 1 'Generated API file lost its openapi-typescript header. Regenerate it (npm run gen:broker-api) instead of editing it.'
            }
        }
        # Item 4 - a migration already in Base is never edited or removed.
        if ($c.Status -ne 'A' -and $c.Old -match $migrationPattern -and $c.Old -notmatch $snapshotPattern) {
            if ($null -ne (Get-BaseText $mb $c.Old)) {
                Add-Finding 4 'BLOCK' $c.Old 0 'Published migration was edited, renamed or removed (ADR-0045). Restore it and create a new migration.'
            }
        }
        if ($c.Status -eq 'D') { continue }
        # Item 32 - a new ADR number already taken in Base by another file (PR 2267). Base, not the
        # merge-base: the collision comes from what entered the master after the branch point.
        if ($c.Status -ne 'M' -and $p -match '^docs/adr/(\d{4})-[^/]+\.md$') {
            $number = $Matches[1]
            $taken = @($baseAdrs | Where-Object { $_ -match "^docs/adr/$number-" -and $_ -ne $p })
            if ($taken.Count) { Add-Finding 32 'BLOCK' $p 0 "ADR $number already exists in $Base as $($taken[0]). Renumber this ADR to the next free number and update every citation and the vocabulary line." }
        }
        foreach ($a in Get-Added $p) {
            # Item 9 - evidence that lives only on this machine.
            if ($p -match '^(docs|backlog)/.+\.md$' -and $a.Text -match '(?i)%TEMP%|AppData[\\/]Local[\\/]Temp') {
                Add-Finding 9 'WARN' $p $a.Line 'Local temp path in docs. Attach the evidence to the WI or commit it under docs/releases/.'
            }
            # Item 9 - a pointer nobody else can open: tmp/ is gitignored, ~/.claude is one machine,
            # a personal OneDrive or a claude.ai artifact needs the author's account (PRs 2122, 2254, 2396, 2443).
            elseif ($p -match '^(docs|backlog|\.cursor/plans)/.+\.md$' -and $a.Text -match '(?i)(?<![\w./-])tmp/[\w.-]|~[\\/]\.claude[\\/]|%USERPROFILE%[\\/]\.claude|-my\.sharepoint\.com/|claude\.ai/(code/)?artifact') {
                Add-Finding 9 'WARN' $p $a.Line 'Pointer outside Git (tmp/, ~/.claude, personal OneDrive or claude.ai artifact). Version the file under backlog/tasks/assets or docs/, attach it to the PR, or keep only the measured value.'
            }
            # Item 33 - a pending-owner marker must not reach the merge (PRs 2267, 2303, 2423).
            if ($p -match '^(docs|backlog|\.cursor/plans)/.+\.md$' -and $a.Text -match '(?i)\bowner\b' -and $a.Text -match '(?i)(aval|aprova\S{1,3}o|confirma\S{1,3}o|ratifica\S{1,3}o)\s+(do\s+owner\s+)?pendente|pendente\s+de\s+(aval|aprova\S{1,3}o|confirma\S{1,3}o|ratifica\S{1,3}o)\s+do\s+owner|aguardando\s+(a\s+|o\s+)?(aval|aprova\S{1,3}o|confirma\S{1,3}o|ratifica\S{1,3}o)\s+do\s+owner|pendente\s*:\s*(aval|aprova\S{1,3}o|confirma\S{1,3}o|ratifica\S{1,3}o)\s+do\s+owner') {
                Add-Finding 33 'WARN' $p $a.Line 'Pending-owner marker. When the owner decides, write "decisao do owner, <date>" with the thread; until then list the pending item in the PR description.'
            }
            # Item 34 - the design system never imports core (PR 2448, broker-select).
            if ($p -match '^platform/frontend/libs/design-system/.+\.ts$' -and $a.Text -match "\bfrom\s+['""](core(/[^'""]*)?|[^'""]*/core/src/[^'""]*)['""]|\bimport\s*\(\s*['""]core(/[^'""]*)?['""]") {
                Add-Finding 34 'BLOCK' $p $a.Line 'The design system imports core. Keep the helper in the design system or take it as an input.'
            }
            # Item 35 - a feature does not target Material internals (PR 2129, rule 036).
            if ($p -match '^platform/frontend/libs/(features|[^/]+/features)/.+\.scss$' -and ($a.Text -replace '//.*$', '') -match '\.(mat-mdc|mdc)-[\w-]') {
                Add-Finding 35 'WARN' $p $a.Line 'Material internal class in a feature style (rule 036). Use the broker-* API, or point out the gap.'
            }
            # Item 12 - native form controls, buttons and Material spinners in feature templates.
            if ($p -match $featureHtmlPattern -and $a.Text -match '<(input|select|textarea|button|mat-spinner|mat-progress-spinner)\b') {
                Add-Finding 12 'WARN' $p $a.Line "Native or Material <$($Matches[1])> in a feature template. Use the broker-* component; point out the gap if one is missing."
            }
            # Item 21 - $any() silences the type checker in a template (PR 2113); `as any` in app code.
            if ($p -match '^platform/frontend/' -and $p -match '\.(html|ts)$' -and $p -notmatch '\.spec\.ts$' -and $p -notmatch '/generated/') {
                if ($a.Text -match '\$any\s*\(') {
                    Add-Finding 21 'BLOCK' $p $a.Line '$any() in a template or component. Type the handler (e.g. $event as typed in the component method) instead of casting away the type.'
                }
                elseif ($p -match '\.ts$' -and $a.Text -match '\bas\s+any\b' -and $a.Text -notmatch '^\s*(//|\*)') {
                    Add-Finding 21 'WARN' $p $a.Line '`as any` in app code. Type it, or justify it in a comment.'
                }
            }
            # Item 22 - a new modal uses broker-dialog directly (rule 044), not lc-dialog.
            if ($p -match '^platform/frontend/.+\.html$' -and $a.Text -match '<lc-dialog\b') {
                Add-Finding 22 'WARN' $p $a.Line 'lc-dialog in new markup. A new modal uses broker-dialog directly (rule 044).'
            }
            # Item 25 - UI tests do not read computed CSS in jsdom.
            if ($p -match '^platform/frontend/.+\.spec\.ts$' -and $a.Text -match '\bgetComputedStyle\s*\(') {
                Add-Finding 25 'WARN' $p $a.Line 'getComputedStyle in a jsdom test. Assert the class or attribute, and measure the layout in a real browser.'
            }
            # Item 31 - an expected failure leaves through Result + ToProblemDetails (errorCode for the
            # frontend); a throw in a feature handler or endpoint needs a comment saying why Result does not fit.
            # String literals are blanked first, so a URL in a message is not read as a comment.
            $code31 = $a.Text -replace '@?"(?:[^"\\]|\\.)*"', '""'
            if ($p -match '^platform/backend/src/.+\.(Application/Features|Api/Endpoints)/.+\.cs$' -and $code31 -match '\bthrow\s+new\b' -and $code31 -notmatch '^\s*(//|/\*|\*)' -and $code31 -notmatch '\bthrow\s+new\b.*//(?!/)') {
                $lines = ((Get-CurrentText $p) -replace "`r`n", "`n") -split "`n"
                # Walk up over blank lines, a lone `{` (Allman) and the earlier lines of the same statement.
                # A trailing comment on an earlier line is code, not the justification: strip it before reading the end.
                $i = $a.Line - 2; $steps = 0
                while ($i -ge 0 -and $steps -lt 30) {
                    $t = $lines[$i].Trim()
                    if ($t -match '^(//|/\*|\*)' -or $t -match '^(#|\[.*\]$)') { break }
                    $code = (($t -replace '@?"(?:[^"\\]|\\.)*"', '""') -replace '\s*//.*$', '') -replace '\s*/\*.*\*/$', ''
                    if ($code -ne '' -and $code -ne '{' -and $code -match '[;{}]$') { break }
                    $i--; $steps++
                }
                $prev = if ($i -ge 0) { $lines[$i].Trim() } else { '' }
                # A `///` XML doc says what the member does, not why Result does not fit.
                if ($prev -notmatch '^(//(?!/)|/\*(?!\*)|\*)') {
                    Add-Finding 31 'BLOCK' $p $a.Line 'throw in a feature handler or endpoint becomes a generic 500 without errorCode. Return Result.Failure(Error.X(code, ...)) and ToProblemDetails(), or write a comment right above saying why Result does not fit (invariant, infrastructure, background job).'
                }
            }
            # Item 2 - !important in a shared lib reaches every app that consumes it (PR 1776).
            if ($p -match $sharedPattern -and $p -match '\.scss$' -and $a.Text -match '!important') {
                Add-Finding 2 'WARN' $p $a.Line '!important in a shared style. It reaches every app and control; scope it to the screen.'
            }
            if ($p -match '^platform/frontend/.+\.scss$') {
                # Item 13 - fixed hex colors outside a var() fallback.
                $code = ($a.Text -replace '//.*$', '') -replace 'var\(\s*--[\w-]+\s*,\s*#[0-9a-fA-F]{3,8}\s*\)', ''
                if ($code -match '#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})\b') {
                    Add-Finding 13 'WARN' $p $a.Line 'Fixed hex color. Use var(--md-*, #fallback).'
                }
                # Item 24 - positional selectors break when the markup order changes (PR 1972).
                if ($a.Text -match ':nth-(child|of-type|last-child)\s*\(') {
                    Add-Finding 24 'WARN' $p $a.Line 'Positional selector. It breaks when the order or markup changes; target a class instead.'
                }
                # Item 14 - ::ng-deep needs a written justification.
                if ($a.Text -match '::ng-deep' -and $a.Text -notmatch '//|/\*') {
                    $lines = ((Get-CurrentText $p) -replace "`r`n", "`n") -split "`n"
                    # Walk up over blank lines and the other selectors of the same rule.
                    $i = $a.Line - 2
                    while ($i -ge 0 -and ([string]::IsNullOrWhiteSpace($lines[$i]) -or $lines[$i].TrimEnd().EndsWith(','))) { $i-- }
                    $prev = if ($i -ge 0) { $lines[$i].Trim() } else { '' }
                    if ($prev -notmatch '^(//|/\*)' -and $prev -notmatch '\*/$') {
                        if (Test-JustifiedDeep $lines) { Add-Finding 14 'WARN' $p $a.Line '::ng-deep without its own comment; another ::ng-deep in this file is justified. Confirm the same reason applies.' }
                        else { Add-Finding 14 'BLOCK' $p $a.Line '::ng-deep without a justification comment right above its rule (rule 070).' }
                    }
                }
            }
        }
    }

    # Item 36 - a new backend error code has copy in the frontend (PRs 2296, 2314, 2429). Codes are the
    # dotted lowercase literals on added lines that build an Error or name a *Code constant.
    $newCodes = [ordered]@{}
    foreach ($c in $changes | Where-Object { $_.Status -ne 'D' -and $_.Path -match '^platform/backend/src/.+\.cs$' -and $_.Path -notmatch '/Migrations/' }) {
        foreach ($a in Get-Added $c.Path) {
            if ($a.Text -notmatch '\bError\.(Validation|NotFound|Conflict|Forbidden|Failure)\s*\(|\bnew\s+Error\s*\(|\b\w*Code\s*=\s*"') { continue }
            foreach ($m in [regex]::Matches($a.Text, '"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)"')) {
                if (-not $newCodes.Contains($m.Groups[1].Value)) { $newCodes[$m.Groups[1].Value] = [pscustomobject]@{ Path = $c.Path; Line = $a.Line } }
            }
        }
    }
    if ($newCodes.Count) {
        $copyFiles = @(@((Invoke-Git @('ls-files', 'platform/frontend')).Lines) + @($changes | Where-Object { $_.Status -ne 'D' } | ForEach-Object Path) |
            Where-Object { $_ -match '^platform/frontend/.+error-copy[^/]*\.ts$' -and $_ -notmatch '\.spec\.ts$' } | Sort-Object -Unique)
        if (-not $copyFiles.Count) { Add-Finding 36 'UNVERIFIED' '' 0 'No *error-copy*.ts file found under platform/frontend; copy of new error codes not checked.' }
        else {
            $copyText = (@($copyFiles | ForEach-Object { Get-CurrentText $_ }) -join "`n")
            foreach ($code in $newCodes.Keys) {
                if ($copyText -notmatch ('[''"`]' + [regex]::Escape($code) + '[''"`]')) {
                    $where = $newCodes[$code]
                    Add-Finding 36 'WARN' $where.Path $where.Line "Error code $code has no copy in the frontend error-copy files. Add the pt-BR message (ERROR_COPY_PT, or the admin-web copy) in this PR."
                }
            }
        }
    }

    # Item 3 - API contracts come from the generated schemas. Schema names are the
    # backend record names, so the check needs neither the API nor the generator.
    $schemas = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $generatedFiles = @((Invoke-Git @('ls-files')).Lines + @($changes | ForEach-Object Path) | Where-Object { $_ -match $generatedApiPattern } | Sort-Object -Unique)
    foreach ($p in $generatedFiles) {
        $text = Get-CurrentText $p
        if ($null -eq $text) { continue }
        # Entries sit at the indent of the first code line inside `schemas: {`, whatever the formatter.
        $indent = -1; $entry = -1
        foreach ($line in (($text -replace "`r`n", "`n") -replace "`t", '    ') -split "`n") {
            if ($indent -lt 0) { if ($line -match '^(\s*)schemas\s*:\s*\{') { $indent = $Matches[1].Length }; continue }
            if ($line -match '^(\s*)\}' -and $Matches[1].Length -le $indent) { break }
            if ($entry -lt 0) {
                if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*(/\*|\*|//)') { continue }
                $entry = ($line -replace '^(\s*).*$', '$1').Length
            }
            if ($line -match '^(\s*)["'']?([\w.-]+)["'']?\??\s*:' -and $Matches[1].Length -eq $entry) { [void]$schemas.Add($Matches[2]) }
        }
    }
    if ($generatedFiles.Count -gt 0 -and $schemas.Count -eq 0) {
        Add-Finding 3 'UNVERIFIED' $generatedFiles[0] 0 'No components.schemas entries found in the generated API types; hand-declared contract types were not checked.'
    }
    $contractSuffixes = @('Dto', 'Request', 'Response', 'Body')
    $backendContracts = [ordered]@{}
    # Infrastructure holds third-party payloads (webhooks), not the API's own contracts.
    foreach ($c in $changes | Where-Object { $_.Status -ne 'D' -and $_.Path -match '^platform/backend/src/.+\.cs$' -and $_.Path -notmatch '[./]Infrastructure/' }) {
        foreach ($a in Get-Added $c.Path) {
            if ($a.Text -match '\bpublic\s+(?:(?:sealed|abstract|partial|readonly)\s+)*(?:record\s+(?:class\s+|struct\s+)?|class\s+)(\w+(?:Dto|Request|Response|Body))\b' -and -not $backendContracts.Contains($Matches[1])) {
                $backendContracts[$Matches[1]] = [pscustomobject]@{ Path = $c.Path; Line = $a.Line }
            }
        }
    }
    # A - a hand-declared type in an HTTP contract file that a schema already gives, or will give.
    foreach ($c in $changes | Where-Object { $_.Status -ne 'D' -and $_.Path -match '^platform/frontend/.+-api\.model\.ts$' }) {
        $lines = $null
        foreach ($a in Get-Added $c.Path) {
            if ($a.Text -notmatch '^\s*export\s+(?:interface\s+(\w+)([^{]*)|type\s+(\w+)\s*(?:<[^=]*>)?\s*=(.*))') { continue }
            # The right side of a type, or the extends clause of an interface.
            # A wrapped right side (`Omit<`, `(`, `|`) continues on the next lines; an interface body does not count.
            if ($Matches[1]) { $name = $Matches[1]; $rhs = $Matches[2]; $wrapped = $rhs.Trim() -match '[<,]$' }
            else { $name = $Matches[3]; $rhs = $Matches[4]; $wrapped = $rhs.Trim() -match '^$|[<(|&,]$' }
            if ($wrapped) {
                if ($null -eq $lines) { $lines = ((Get-CurrentText $c.Path) -replace "`r`n", "`n") -split "`n" }
                for ($k = $a.Line; $k -lt [Math]::Min($a.Line + 2, $lines.Count); $k++) { $rhs += ' ' + $lines[$k] }
            }
            if ($rhs -match '\b(Schemas|components)\s*\[') { continue }
            $candidates = @($name) + @($contractSuffixes | ForEach-Object { "$name$_" })
            $schema = $candidates | Where-Object { $schemas.Contains($_) } | Select-Object -First 1
            if ($schema) { Add-Finding 3 'BLOCK' $c.Path $a.Line "$name is declared by hand; the generated schema $schema exists. Use Schemas['$schema']."; continue }
            $contract = $candidates | Where-Object { $backendContracts.Contains($_) } | Select-Object -First 1
            if ($contract) { Add-Finding 3 'BLOCK' $c.Path $a.Line "$name is declared by hand for $contract, which this branch added to the backend. Start the API, run npm run gen:broker-api, and use Schemas['$contract']." }
        }
    }
    # B - a backend contract the generated files do not know yet: the generator did not run.
    if ($schemas.Count -gt 0) {
        foreach ($name in $backendContracts.Keys | Where-Object { -not $schemas.Contains($_) }) {
            $where = $backendContracts[$name]
            Add-Finding 3 'WARN' $where.Path $where.Line "$name is not in the generated API types. If the API exposes it, start the API and run npm run gen:broker-api (or gen:admin-api)."
        }
    }

    # Item 4 - new migrations: RLS FORCE and contraction.
    $newMigrations = @($changes | Where-Object { $_.Status -eq 'A' -and $_.Path -match $migrationPattern -and $_.Path -notmatch $snapshotPattern } | ForEach-Object Path)
    $enabled = @{}; $forced = @{}
    $rlsTable = '(?i)ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?([\w\."]+)\s+'
    foreach ($p in $newMigrations | Where-Object { $_ -notmatch $designerPattern }) {
        $text = Get-CurrentText $p
        if ($null -eq $text) { continue }
        $up = [regex]::Match($text, '(?s)void\s+Up\s*\(.*?(?=void\s+Down\s*\(|\z)').Value
        foreach ($m in [regex]::Matches($up, $rlsTable + 'ENABLE\s+ROW\s+LEVEL\s+SECURITY')) { $enabled[($m.Groups[1].Value -replace '"', '').ToLowerInvariant()] = $p }
        foreach ($m in [regex]::Matches($up, $rlsTable + 'FORCE\s+ROW\s+LEVEL\s+SECURITY')) { $forced[($m.Groups[1].Value -replace '"', '').ToLowerInvariant()] = $true }
        if ($up -match '\b(DropColumn|DropTable)\s*[<(]') {
            Add-Finding 4 'WARN' $p 0 "$($Matches[1]) in Up. Contraction goes in its own migration, in a later deploy (ADR-0049 section 8)."
        }
    }
    foreach ($table in $enabled.Keys | Sort-Object) {
        if (-not $forced.ContainsKey($table)) { Add-Finding 4 'BLOCK' $enabled[$table] 0 "Table $table enables RLS without FORCE ROW LEVEL SECURITY (ADR-0009)." }
    }
    # Item 37 - each new RLS table has a test that reads relforcerowsecurity (PR 2254). git grep
    # --untracked also sees a test file the branch has not committed yet.
    if ($enabled.Count) {
        $rlsTests = Invoke-Git @('grep', '-l', '--untracked', '-e', 'relforcerowsecurity', '--', 'platform/backend/tests') -AllowFail
        if ($rlsTests.Code -gt 1) { Add-Finding 37 'UNVERIFIED' '' 0 'git grep could not search platform/backend/tests for relforcerowsecurity.' }
        else {
            $rlsText = (@($rlsTests.Lines | Where-Object { $_ } | ForEach-Object { Get-CurrentText $_ }) -join "`n")
            foreach ($table in $enabled.Keys | Sort-Object) {
                $name = ($table -split '\.')[-1]
                if ($rlsText -notmatch ('(?<![\w])' + [regex]::Escape($name) + '(?![\w])')) {
                    Add-Finding 37 'WARN' $enabled[$table] 0 "No test with relforcerowsecurity names table $name. Add one in the mold of ImportBatchesIntegrationTests (relrowsecurity and relforcerowsecurity true)."
                }
            }
        }
    }
    # Item 38 - a new migration dated before the newest one Base already has in the same folder (PRs 2429, 2195).
    foreach ($p in $newMigrations | Where-Object { $_ -notmatch $designerPattern }) {
        if ([IO.Path]::GetFileName($p) -notmatch '^(\d{14})_') { continue }
        $stamp = $Matches[1]
        $dir = $p.Substring(0, $p.LastIndexOf('/') + 1)
        $newest = @((Invoke-Git @('ls-tree', '--name-only', $Base, $dir) -AllowFail).Lines |
            ForEach-Object { [IO.Path]::GetFileName($_) } | Where-Object { $_ -match '^\d{14}_' -and $_ -notmatch $designerPattern } | Sort-Object | Select-Object -Last 1)
        if ($newest.Count -and $newest[0].Substring(0, 14) -gt $stamp) {
            Add-Finding 38 'WARN' $p 0 "Migration is dated before $($newest[0]), already in $Base. Run the Architecture tests with $Base merged and confirm the snapshot has both sides and no pending model change."
        }
    }

    # Item 10 - the PR gate (pipeline 158) must have run green over the last iteration.
    # Skipped silently when the branch has no PR (the delegation to 158 then lapses, see /execute-ig step 10).
    $branchName = @((Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFail).Lines)[0]
    $gateRuns = $null; $prNo = $PrNumber; $gateLookupFailed = $false
    if ($GateRunsJson) { $parsedGate = Get-Content -Raw -Encoding UTF8 -LiteralPath $GateRunsJson | ConvertFrom-Json; $gateRuns = @($parsedGate); if (-not $prNo) { $prNo = -1 } }
    elseif (-not $NoFetch -and ($prNo -or ($branchName -and $branchName -ne 'HEAD'))) {
        if (-not $prNo) {
            $prs = Get-AzJson @('repos', 'pr', 'list', '--organization', $AzOrg, '--project', $AzProject, '--source-branch', $branchName, '--status', 'active')
            if ($null -eq $prs) { $gateLookupFailed = $true } elseif (@($prs).Count -gt 0) { $prNo = [int](@($prs)[0].codeReviewId) }
        }
        if ($prNo -gt 0) {
            $gateRuns = Get-AzJson @('pipelines', 'runs', 'list', '--organization', $AzOrg, '--project', $AzProject, '--pipeline-ids', "$GatePipelineId", '--branch', "refs/pull/$prNo/merge", '--top', '20')
            if ($null -eq $gateRuns) { $gateLookupFailed = $true }
        }
    }
    # The gate runs after this check (it validates what the dev pushes), so nothing here may be UNVERIFIED:
    # a gate that cannot be read or matched locally only warns, and the exit stays 0 without other findings.
    # Item 39 - the PR has a linked work item (PR 2314). Only warns, like the rest of the PR lookup.
    # Decided on the raw JSON: in Windows PowerShell an empty array from ConvertFrom-Json reads as $null.
    $wiRaw = $null
    if ($PrWorkItemsJson) { $wiRaw = Get-Content -Raw -Encoding UTF8 -LiteralPath $PrWorkItemsJson }
    elseif (-not $NoFetch -and $prNo -gt 0) {
        $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = & az repos pr work-item list --id "$prNo" --organization $AzOrg -o json 2>$null; if ($LASTEXITCODE -eq 0) { $wiRaw = ($out -join "`n") } else { $wiRaw = '' } }
        catch { $wiRaw = '' } finally { $ErrorActionPreference = $previous }
    }
    if ($null -ne $wiRaw) {
        if ($wiRaw -notmatch '^\s*\[') { Add-Finding 39 'WARN' '' 0 "Could not read the work items linked to PR $prNo (az login?)." }
        elseif ($wiRaw -match '^\s*\[\s*\]\s*$') { Add-Finding 39 'WARN' '' 0 "PR $prNo has no linked work item. Link the WI in the PR, not only in the branch name." }
    }
    if ($gateLookupFailed) { Add-Finding 10 'WARN' '' 0 "Could not read the PR or the runs of pipeline $GatePipelineId (az login?). Gate freshness not checked." }
    elseif ($prNo -and $null -ne $gateRuns) {
        $ordered = @($gateRuns | Where-Object { $null -ne $_ } | Sort-Object { [int](Get-Prop $_ 'id') } -Descending)
        $docsOnly = '(^|/)(docs|backlog|\.cursor)/|\.md$'
        $headOf = {
            param($run)
            $sha = [string](Get-Prop $run 'sourceVersion')
            $r = Invoke-Git @('rev-parse', '--verify', '--quiet', "$sha^2") -AllowFail
            if ($r.Code -eq 0 -and $r.Lines.Count) { $r.Lines[0] } else { $null }
        }
        $since = {
            param($head)
            $n = [int]@((Invoke-Git @('rev-list', '--count', "$head..HEAD")).Lines)[0]
            if ($n -eq 0) { return $null }
            $files = @((Invoke-Git @('diff', '--name-only', "$head..HEAD")).Lines | Where-Object { $_ -and $_ -notmatch $docsOnly })
            [pscustomobject]@{ Count = $n; Code = $files }
        }
        if ($ordered.Count -eq 0) {
            Add-Finding 10 'WARN' '' 0 "Pipeline $GatePipelineId has no run on refs/pull/$prNo/merge. Push the branch and let it run before review."
        } else {
            $latest = $ordered[0]; $id = Get-Prop $latest 'id'; $result = [string](Get-Prop $latest 'result'); $status = [string](Get-Prop $latest 'status')
            if ($status -and $status -ne 'completed') { Add-Finding 10 'WARN' '' 0 "Run $id of pipeline $GatePipelineId is still $status; wait for it before review." }
            $head = & $headOf $latest
            if ($null -eq $head) { Add-Finding 10 'WARN' '' 0 "Run $id covers a merge commit that is not available locally; cannot tell which iteration it validated. The gate runs after this check: push and wait for a run over HEAD." }
            else {
                $after = & $since $head
                if ($after) {
                    $codeNote = if ($after.Code.Count) { "code changed since: $((@($after.Code) | Select-Object -First 5) -join ', ')" } else { 'only docs changed since' }
                    Add-Finding 10 'WARN' '' 0 "The newest run of pipeline $GatePipelineId ($id, $result) validated $($head.Substring(0,9)); $($after.Count) commit(s) came after it ($codeNote). Push and wait for a green run over HEAD."
                }
            }
            if ($status -eq 'completed' -and $result -ne 'succeeded') {
                $green = $ordered | Where-Object { [string](Get-Prop $_ 'result') -eq 'succeeded' } | Select-Object -First 1
                $greenNote = 'no green run on this PR'
                if ($green) {
                    $gh = & $headOf $green
                    $gs = if ($gh) { & $since $gh } else { $null }
                    $greenNote = "last green run $(Get-Prop $green 'id')"
                    if ($gs -and $gs.Code.Count) { $greenNote += " is $($gs.Count) commit(s) behind HEAD with code changed after it" }
                    elseif ($gs) { $greenNote += ' is behind HEAD only by docs' }
                }
                Add-Finding 10 'WARN' '' 0 "Run $id of pipeline $GatePipelineId finished $result; $greenNote. A red run is fixed and pushed again."
            }
            if ($status -eq 'completed') {
                $timeline = if ($GateTimelineJson) { Get-Content -Raw -Encoding UTF8 -LiteralPath $GateTimelineJson | ConvertFrom-Json }
                            else { Get-AzJson @('devops', 'invoke', '--organization', $AzOrg, '--area', 'build', '--resource', 'timeline', '--route-parameters', "project=$AzProject", "buildId=$id", '--api-version', '7.1') }
                if ($null -eq $timeline) { Add-Finding 10 'WARN' '' 0 "Could not read the timeline of run $id; skipped HostSmoke not checked." }
                else {
                    $skipped = @($timeline.records | Where-Object { $_.type -eq 'Task' -and $_.name -match 'HostSmoke' -and $_.result -eq 'skipped' } | ForEach-Object { $_.name })
                    if ($skipped.Count) { Add-Finding 10 'WARN' '' 0 "Run $id skipped HostSmoke task(s): $($skipped -join ', '). The gate did not prove them." }
                }
            }
        }
    }
} catch {
    # A crash never reads as clean or as a finding to fix in the code.
    Add-Finding 0 'UNVERIFIED' '' 0 "The check itself failed: $($_.Exception.Message)"
} finally { if ($previousEncoding) { [Console]::OutputEncoding = $previousEncoding } }

$exit = if (@($findings | Where-Object Severity -eq 'BLOCK').Count) { 1 } elseif (@($findings | Where-Object Severity -eq 'UNVERIFIED').Count) { 2 } else { 0 }
$status = @('CLEAN', 'BLOCKED', 'UNVERIFIED')[$exit]
if ($AsJson) {
    [pscustomobject]@{ Status = $status; MergeBase = $mb; Findings = @($findings) } | ConvertTo-Json -Depth 4 -Compress
} else {
    foreach ($f in $findings) {
        $where = if ($f.Path) { if ($f.Line) { " $($f.Path):$($f.Line)" } else { " $($f.Path)" } } else { '' }
        Write-Output "$($f.Severity) [item $($f.Item)]$where - $($f.Message)"
    }
    Write-Output "Owner blockers check: $status (merge-base $mb)"
}
exit $exit
