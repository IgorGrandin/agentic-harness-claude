[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkItemOrPlan,
    [string]$PlanDirectory = '.cursor/plans',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PlanParts([string]$Text) {
    $frontMatter = ''
    $body = $Text
    if ($Text -match '(?ms)^---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)') {
        $frontMatter = $Matches[1]
        $body = $Text.Substring($Matches[0].Length)
    }
    [pscustomobject]@{ FrontMatter = $frontMatter; Body = $body }
}

function Get-PlanIdentity([IO.FileInfo]$File, [string]$FrontMatter, [string]$Body, [string]$WantedId) {
    if ($File.BaseName -match '(?i)^(?:wi[-_ ]?)?(\d+)(?=$|[-_. ])' -and $Matches[1] -eq $WantedId) { return 'filename' }
    $identityKeys = '(?:work[_ -]?item(?:[_ -]?id)?|wi(?:[_ -]?id)?|azure[_ -]?work[_ -]?item|backlog[_ -]?id|title)'
    foreach ($line in ($FrontMatter -split "`r?`n")) {
        if ($line -match ('(?i)^\s*' + $identityKeys + '\s*:\s*["'']?(?:WI[-# ]?)?(\d+)(?:\b|$)')) {
            if ($Matches[1] -eq $WantedId) { return 'frontmatter' }
        }
    }
    $headerLines = @($Body -split "`r?`n" | Select-Object -First 35)
    foreach ($line in $headerLines) {
        if ($line -match '(?i)^\s*#{1,2}\s+(?:\[\s*)?WI[-# ]?(\d+)\b' -and $Matches[1] -eq $WantedId) { return 'title' }
        if ($line -match '(?i)^\s*(?:\*\*)?(?:WI|Work Item)\s*(?:\*\*)?\s*[:#]\s*(?:WI[-# ]?)?(\d+)\s*$' -and $Matches[1] -eq $WantedId) { return 'body-metadata' }
    }
    return $null
}

function Convert-PlanStatus([string]$Value) {
    $normalized = ($Value.Trim().Trim('"', "'", '`').ToLowerInvariant() -replace '[ -]', '_')
    switch -Regex ($normalized) {
        '^(pending|todo|not_started|notstarted|open)$' { return 'pending' }
        '^(in_progress|inprogress|active|doing)$' { return 'in_progress' }
        '^(reopened|re_opened|returned)$' { return 'reopened' }
        '^(blocked|waiting)$' { return 'blocked' }
        '^(completed|complete|done|closed)$' { return 'completed' }
        '^(cancelled|canceled|skipped|not_applicable)$' { return 'closed' }
        default { return 'unknown' }
    }
}

function Get-WorkItems([string]$FrontMatter, [string]$Body) {
    $items = [Collections.Generic.List[object]]::new()
    $frontMatterTodos = [Collections.Generic.List[string]]::new()
    $inTodos = $false
    $current = $null
    foreach ($line in ($FrontMatter -split "`r?`n")) {
        if ($line -match '^todos\s*:\s*(?:\[\s*\])?\s*$') { $inTodos = $true; continue }
        if ($inTodos -and $line -match '^\S') { $inTodos = $false; if ($current) { $frontMatterTodos.Add(($current -join "`n")); $current = $null } }
        if (-not $inTodos) { continue }
        if ($line -match '^\s*-\s*(.*)$') {
            if ($current) { $frontMatterTodos.Add(($current -join "`n")) }
            $current = [Collections.Generic.List[string]]::new()
            $current.Add($Matches[1])
        } elseif ($null -ne $current) { $current.Add($line) }
    }
    if ($current) { $frontMatterTodos.Add(($current -join "`n")) }
    foreach ($block in $frontMatterTodos) {
        $status = 'unknown'; $title = ''; $id = ''
        if ($block -match '(?im)^\s*status\s*:\s*([^\r\n#]+)') { $status = Convert-PlanStatus $Matches[1] }
        if ($block -match '(?im)^\s*(?:id|key|slice)\s*:\s*([^\r\n#]+)') { $id = $Matches[1].Trim().Trim('"', "'") }
        if ($block -match '(?im)^\s*(?:content|title|name|description)\s*:\s*([^\r\n#]+)') { $title = $Matches[1].Trim().Trim('"', "'") }
        if (-not $title) { $title = $id }
        $items.Add([pscustomobject]@{ Id=$id; Title=$title; Status=$status; Source='frontmatter' })
    }
    if ($items.Count -gt 0) { return @($items) }

    foreach ($line in ($Body -split "`r?`n")) {
        if ($line -match '^\s*[-*]\s+\[([ xX])\]\s+(.+?)\s*$') {
            $checkState = $Matches[1]
            $checkTitle = $Matches[2].Trim()
            $status = if ($checkState -match '[xX]') { 'completed' } else { 'pending' }
            $items.Add([pscustomobject]@{ Id=''; Title=$checkTitle; Status=$status; Source='checklist' })
            continue
        }
        if ($line -match '(?i)^\s*(?:#{2,6}\s*)?(?:slice|fatia)\s+([A-Za-z0-9._-]+)\s*(?:[:—–-]\s*|\s+status\s*[:=]\s*)(pending|in[_ -]?progress|reopened|blocked|completed|done)\b\s*(.*)$') {
            $sliceId = $Matches[1]; $sliceStatus = $Matches[2]; $sliceTitle = $Matches[3].Trim()
            $items.Add([pscustomobject]@{ Id=$sliceId; Title=$sliceTitle; Status=(Convert-PlanStatus $sliceStatus); Source='slice-status' })
        }
    }
    return @($items)
}

function Get-PlanOrder([string]$FrontMatter, [string[]]$CandidateStems) {
    $order = $null
    if ($FrontMatter -match '(?im)^\s*(?:execution_order|plan_order)\s*:\s*(\d+)\s*$') { $order = [int]$Matches[1] }
    $dependencies = [Collections.Generic.List[string]]::new()
    $inDependencies = $false
    foreach ($line in ($FrontMatter -split "`r?`n")) {
        if ($line -match '^\s*(?:depends_on|plan_dependencies)\s*:\s*(.*)$') {
            $inDependencies = $true
            $tail = $Matches[1].Trim().Trim('[',']')
            foreach ($token in ($tail -split '[, ]+' | Where-Object { $_ })) { $dependencies.Add($token.Trim('"', "'")) }
            continue
        }
        if ($inDependencies -and $line -match '^\s*-\s*(.+?)\s*$') { $dependencies.Add($Matches[1].Trim().Trim('"', "'")); continue }
        if ($inDependencies -and $line -match '^\S') { $inDependencies = $false }
    }
    $resolved = @($dependencies | ForEach-Object { $dep = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileName($_)); if ($CandidateStems -contains $dep) { $dep } } | Select-Object -Unique)
    [pscustomobject]@{ Order=$order; Dependencies=$resolved }
}

$argument = $WorkItemOrPlan.Trim().Trim('"', "'")
if (Test-Path -LiteralPath $argument -PathType Leaf) {
    $explicitPath = [IO.Path]::GetFullPath($argument)
    $explicitText = Get-Content -LiteralPath $explicitPath -Raw -Encoding UTF8
    $explicitParts = Get-PlanParts $explicitText
    $explicitItems = @(Get-WorkItems $explicitParts.FrontMatter $explicitParts.Body)
    $explicitPending = @($explicitItems | Where-Object Status -in @('pending','in_progress','reopened'))
    $explicitBlocked = @($explicitItems | Where-Object Status -eq 'blocked')
    $explicitComplete = @($explicitItems | Where-Object Status -eq 'completed')
    $explicitUnknown = @($explicitItems | Where-Object Status -eq 'unknown')
    $explicitGatePending = @($explicitPending | Where-Object { $_.Title -match '(?i)\b(final\s+)?gate\b|suite completa|pronto' })
    $explicitImplementationPending = @($explicitPending | Where-Object { $_.Title -notmatch '(?i)\b(final\s+)?gate\b|suite completa|pronto' })
    $explicitProgress = if ($explicitItems.Count -eq 0 -or $explicitUnknown.Count -gt 0) { 'unknown' }
        elseif ($explicitImplementationPending.Count -gt 0) { 'active' }
        elseif ($explicitBlocked.Count -gt 0) { 'blocked' }
        elseif ($explicitGatePending.Count -gt 0) { 'gate_pending' }
        else { 'complete' }
    $explicitCandidate = [pscustomobject]@{
        Path=$explicitPath; Name=[IO.Path]::GetFileName($explicitPath); Objective=$null; MatchSource='explicit'
        Progress=$explicitProgress; PendingCount=$explicitPending.Count; ImplementationPendingCount=$explicitImplementationPending.Count
        GatePendingCount=$explicitGatePending.Count; BlockedCount=$explicitBlocked.Count; CompletedCount=$explicitComplete.Count
        UnknownCount=$explicitUnknown.Count
        RemainingItems=@($explicitPending + $explicitBlocked | ForEach-Object { [pscustomobject]@{ Id=$_.Id; Title=$_.Title; Status=$_.Status; Source=$_.Source } })
    }
    $result = [pscustomobject]@{ SchemaVersion=1; Requested=$argument; Outcome='explicit'; SelectedPlan=$explicitPath; SelectionReason='explicit plan path; status still requires code/evidence review'; Candidates=@($explicitCandidate) }
    if ($AsJson) { $result | ConvertTo-Json -Depth 8 -Compress } else { $result }
    return
}
if ($argument -match '(?i)^WI[-# ]?(\d+)$') { $requestedId = $Matches[1] }
elseif ($argument -match '^\d+$') { $requestedId = $argument }
else { throw "Provide an exact WI number (for example 3572) or an existing plan path: $argument" }

$directory = [IO.Path]::GetFullPath($PlanDirectory)
if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Plan directory not found: $directory" }
$allFiles = @(Get-ChildItem -LiteralPath $directory -File -Filter '*.plan.md' | Sort-Object FullName)
$candidates = [Collections.Generic.List[object]]::new()
foreach ($file in $allFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $parts = Get-PlanParts $text
    $matchSource = Get-PlanIdentity $file $parts.FrontMatter $parts.Body $requestedId
    if (-not $matchSource) { continue }
    $items = @(Get-WorkItems $parts.FrontMatter $parts.Body)
    $pending = @($items | Where-Object Status -in @('pending','in_progress','reopened'))
    $blocked = @($items | Where-Object Status -eq 'blocked')
    $completed = @($items | Where-Object Status -eq 'completed')
    $gatePending = @($pending | Where-Object { $_.Title -match '(?i)\b(final\s+)?gate\b|suite completa|pronto' })
    $implementationPending = @($pending | Where-Object { $_.Title -notmatch '(?i)\b(final\s+)?gate\b|suite completa|pronto' })
    $progress = if ($items.Count -eq 0 -or @($items | Where-Object Status -eq 'unknown').Count -gt 0) { 'unknown' }
        elseif ($implementationPending.Count -gt 0) { 'active' }
        elseif ($blocked.Count -gt 0) { 'blocked' }
        elseif ($gatePending.Count -gt 0) { 'gate_pending' }
        else { 'complete' }
    $objective = @($parts.Body -split "`r?`n" | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1)
    if ($objective.Count) { $objective = ($objective[0] -replace '^#\s+','').Trim() } else { $objective = [IO.Path]::GetFileNameWithoutExtension($file.Name) }
    if ($objective.Length -gt 160) { $objective = $objective.Substring(0,157) + '...' }
    $candidates.Add([pscustomobject]@{
        Path=$file.FullName; Name=$file.Name; Objective=$objective; MatchSource=$matchSource; Progress=$progress
        PendingCount=$pending.Count; ImplementationPendingCount=$implementationPending.Count; GatePendingCount=$gatePending.Count
        BlockedCount=$blocked.Count; CompletedCount=$completed.Count; UnknownCount=@($items | Where-Object Status -eq 'unknown').Count
        RemainingItems=@($pending + $blocked | ForEach-Object { [pscustomobject]@{ Id=$_.Id; Title=$_.Title; Status=$_.Status; Source=$_.Source } })
        WorkItems=$items; FrontMatter=$parts.FrontMatter
    })
}

$active = @($candidates | Where-Object Progress -eq 'active')
$selected = $null; $reason = ''
if ($candidates.Count -eq 0) { $outcome = 'no_match' }
elseif ($active.Count -eq 1) { $selected = $active[0]; $reason = 'only exact WI match with implementation work remaining'; $outcome = 'selected' }
elseif ($active.Count -gt 1) {
    $stems = @($active | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
    $orders = @($active | ForEach-Object { Get-PlanOrder $_.FrontMatter $stems })
    $hasOrder = @($orders | Where-Object { $null -ne $_.Order }).Count -eq $active.Count -and @($orders.Order | Select-Object -Unique).Count -eq $active.Count
    if ($hasOrder) {
        $lowest = ($orders.Order | Measure-Object -Minimum).Minimum
        $idx = [array]::IndexOf([object[]]@($orders | ForEach-Object Order),[int]$lowest)
        $selected = $active[$idx]; $reason = "unique explicit execution_order=$lowest"; $outcome='selected'
    } else {
        # A unique active predecessor is selectable only when another active
        # plan explicitly declares it as a dependency. This is evidence of
        # ordering, unlike filename recency or incidental cross-references.
        $predecessors = [Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $orders.Count; $i++) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($active[$i].Name)
            $dependedOn = $false
            for ($j = 0; $j -lt $orders.Count; $j++) {
                if ($i -ne $j -and $orders[$j].Dependencies -contains $stem) { $dependedOn = $true }
            }
            if ($dependedOn) { $predecessors.Add($i) }
        }
        if ($predecessors.Count -eq 1) {
            $selected = $active[$predecessors[0]]; $reason = 'unique explicit dependency predecessor'; $outcome='selected'
        } else { $outcome='ambiguous' }
    }
}
elseif ($candidates.Count -gt 1) { $outcome='ambiguous' }
elseif (@($candidates | Where-Object Progress -eq 'blocked').Count -gt 0) { $outcome='blocked' }
elseif (@($candidates | Where-Object Progress -eq 'gate_pending').Count -gt 0) { $outcome='needs_evidence_review' }
elseif (@($candidates | Where-Object Progress -eq 'unknown').Count -gt 0) { $outcome='needs_status_review' }
else { $outcome='needs_evidence_review' }

$publicCandidates = @($candidates | ForEach-Object {
    [pscustomobject]@{ Path=$_.Path; Name=$_.Name; Objective=$_.Objective; MatchSource=$_.MatchSource; Progress=$_.Progress; PendingCount=$_.PendingCount; ImplementationPendingCount=$_.ImplementationPendingCount; GatePendingCount=$_.GatePendingCount; BlockedCount=$_.BlockedCount; CompletedCount=$_.CompletedCount; UnknownCount=$_.UnknownCount; RemainingItems=$_.RemainingItems }
})
$result = [pscustomobject]@{ SchemaVersion=1; Requested=$argument; WorkItemId=$requestedId; Outcome=$outcome; SelectedPlan=$(if ($selected) { $selected.Path } else { $null }); SelectionReason=$reason; Candidates=$publicCandidates }
if ($AsJson) { $result | ConvertTo-Json -Depth 8 -Compress } else { $result }
