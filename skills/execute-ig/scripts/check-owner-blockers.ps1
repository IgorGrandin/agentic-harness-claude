[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Base = 'origin/master',
    [int]$DeployPipelineId = 139,
    [string]$DeployTarget = 'dev2',
    [string]$DeployRunsJson,
    [switch]$NoFetch,
    [switch]$AsJson
)

# Deterministic part of the owner's recurring blockers list (CLAUDE.local.md).
# Compares the working tree (tracked and untracked) with merge-base(Base, HEAD).
# Item numbers match the list. Exit 0 = clean, 1 = at least one BLOCK,
# 2 = no BLOCK but a check could not run or the script failed (UNVERIFIED, item 0
# for a failure). WARN never changes the exit.
# -DeployRunsJson replaces the Azure DevOps query (test seam): a JSON array shaped
# like `az pipelines runs list` output.

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
        foreach ($a in Get-Added $p) {
            # Item 9 - evidence that lives only on this machine.
            if ($p -match '^(docs|backlog)/.+\.md$' -and $a.Text -match '(?i)%TEMP%|AppData[\\/]Local[\\/]Temp') {
                Add-Finding 9 'WARN' $p $a.Line 'Local temp path in docs. Attach the evidence to the WI or commit it under docs/releases/.'
            }
            # Item 12 - native form controls in feature templates.
            if ($p -match $featureHtmlPattern -and $a.Text -match '<(input|select|textarea)\b') {
                Add-Finding 12 'WARN' $p $a.Line "Native <$($Matches[1])> in a feature template. Use the broker-* component; point out the gap if one is missing."
            }
            if ($p -match '^platform/frontend/.+\.scss$') {
                # Item 13 - fixed hex colors outside a var() fallback.
                $code = ($a.Text -replace '//.*$', '') -replace 'var\(\s*--[\w-]+\s*,\s*#[0-9a-fA-F]{3,8}\s*\)', ''
                if ($code -match '#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})\b') {
                    Add-Finding 13 'WARN' $p $a.Line 'Fixed hex color. Use var(--md-*, #fallback).'
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

    # Item 4 - a branch migration deployed to the shared environment is never edited or removed afterwards.
    # Looked up whenever the branch touched migrations, in commits or in the working tree.
    $committedMigrations = @((Invoke-Git @('log', '--name-only', '--format=', "$mb..HEAD")).Lines | Where-Object { $_ -match $migrationPattern })
    $touchesMigrations = $committedMigrations.Count -gt 0 -or @($changes | Where-Object { $_.Path -match $migrationPattern -or ($_.Old -and $_.Old -match $migrationPattern) }).Count -gt 0
    if ($touchesMigrations) {
        $branch = (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')).Lines[0]
        $runs = $null
        if ($branch -eq 'HEAD') { Add-Finding 4 'UNVERIFIED' '' 0 'Detached HEAD: cannot look up deploy runs for this branch.' }
        elseif ($DeployRunsJson) { $parsed = Get-Content -Raw -Encoding UTF8 -LiteralPath $DeployRunsJson | ConvertFrom-Json; $runs = @($parsed) }
        else {
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $raw = & az pipelines runs list --pipeline-ids $DeployPipelineId --branch "refs/heads/$branch" --top 200 -o json 2>$null
                if ($LASTEXITCODE -eq 0) { $parsed = ($raw -join "`n") | ConvertFrom-Json; $runs = @($parsed) }
            } catch { $runs = $null }
            finally { $ErrorActionPreference = $previous }
            if ($null -eq $runs) { Add-Finding 4 'UNVERIFIED' '' 0 "Could not list runs of pipeline $DeployPipelineId (az login?). Branch migrations not checked against $DeployTarget." }
        }
        $branchRuns = 0; $targetedRuns = 0
        foreach ($run in @($runs | Where-Object { $null -ne $_ })) {
            if ((Get-Prop $run 'sourceBranch') -ne "refs/heads/$branch") { continue }
            $branchRuns++
            $target = Get-Prop (Get-Prop $run 'templateParameters') 'deploymentTarget'
            if ($target) { $targetedRuns++ }
            if ($target -ne $DeployTarget) { continue }
            $sha = [string](Get-Prop $run 'sourceVersion'); $id = Get-Prop $run 'id'; $result = [string](Get-Prop $run 'result')
            if ((Invoke-Git @('cat-file', '-e', "$sha^{commit}") -AllowFail).Code -ne 0) {
                Add-Finding 4 'UNVERIFIED' '' 0 "Run $id deployed commit $sha to $DeployTarget, which is not available locally."
                continue
            }
            $severity = if ($result -eq 'canceled') { 'WARN' } else { 'BLOCK' }
            $short = $sha.Substring(0, [Math]::Min(8, $sha.Length))
            # Every migration the branch had added at the deployed commit must still exist, unchanged.
            $deployedSet = @((Invoke-Git @('diff', '--name-only', '--no-renames', '--diff-filter=A', "$mb...$sha")).Lines | Where-Object { $_ -match $migrationPattern -and $_ -notmatch $snapshotPattern })
            foreach ($p in $deployedSet) {
                if ($null -ne (Get-BaseText $mb $p)) { continue }
                $now = Get-CurrentText $p
                if ($null -eq $now) {
                    Add-Finding 4 $severity $p 0 "Deployed to $DeployTarget by run $id ($result, commit $short) and removed afterwards (migrations remove/add?). Restore it from that commit and create a new migration for the change."
                } elseif ((Normalize (Get-BaseText $sha $p)) -ne (Normalize $now)) {
                    Add-Finding 4 $severity $p 0 "Deployed to $DeployTarget by run $id ($result, commit $short) and edited afterwards. Restore the content of that commit and create a new migration."
                }
            }
        }
        if ($branchRuns -gt 0 -and $targetedRuns -eq 0) {
            Add-Finding 4 'UNVERIFIED' '' 0 "Runs of pipeline $DeployPipelineId exist for this branch, but none reports templateParameters.deploymentTarget."
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
