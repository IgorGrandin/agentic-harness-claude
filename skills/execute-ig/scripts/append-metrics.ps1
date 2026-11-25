[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StartedAt,
    [Parameter(Mandatory)][string]$FinishedAt,
    [Parameter(Mandatory)][string]$Plan,
    [Parameter(Mandatory)][string]$Branch,
    [string]$CommitSha = '',
    [Parameter(Mandatory)][string]$RootModel,
    [Parameter(Mandatory)][string]$RootEffort,
    [int]$PeakWorkers = 0,
    [int]$SlicesTotal = 0,
    [int]$SlicesPassed = 0,
    [int]$CorrectionRounds = 0,
    [double]$ImplementationMinutes = 0,
    [double]$SliceReviewMinutes = 0,
    [double]$FocusedVerificationMinutes = 0,
    [double]$IntegrationReviewMinutes = 0,
    [double]$FinalGateMinutes = 0,
    [double]$PostGateReviewMinutes = 0,
    [double]$TotalMinutes = 0,
    [ValidateSet('PASSED','FAILED','NOT_RUN','INVALIDATED')][string]$GateStatus = 'NOT_RUN',
    [string]$GateSha = '',
    [ValidateSet('true','false')][string]$TreeClean = 'false',
    [string]$SliceModels = '{}',
    [string]$InputTokens = '',
    [string]$OutputTokens = '',
    # Product repository. When set, slice_models is read from the Execute-Slice, Execute-Host and
    # Execute-Model trailers of this plan's slice commits on HEAD, so slices done on another host
    # (Antigravity, Codex) are recorded with the model that actually ran them.
    [string]$Repo = '',
    [string]$Path = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\brixbroker\execute-rodadas.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$header = 'started_at;finished_at;plan;branch;commit_sha;root_model;root_effort;peak_workers;slices_total;slices_passed;correction_rounds;implementation_minutes;slice_review_minutes;focused_verification_minutes;integration_review_minutes;final_gate_minutes;post_gate_review_minutes;total_minutes;gate_status;gate_sha;tree_clean;slice_models;input_tokens;output_tokens'
if ($GateStatus -eq 'PASSED' -and ([string]::IsNullOrWhiteSpace($CommitSha) -or $GateSha -ne $CommitSha -or $TreeClean -ne 'true')) { throw 'A passed gate requires matching commit and gate SHA plus a clean tree.' }
if ($StartedAt -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' -or $FinishedAt -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$') { throw 'StartedAt and FinishedAt must be ISO 8601 timestamps with an explicit offset.' }
try { $null = [DateTimeOffset]::Parse($StartedAt); $null = [DateTimeOffset]::Parse($FinishedAt) } catch { throw 'StartedAt and FinishedAt must be valid ISO 8601 timestamps.' }
if (@($PeakWorkers,$SlicesTotal,$SlicesPassed,$CorrectionRounds) | Where-Object { $_ -lt 0 } | Measure-Object | Select-Object -ExpandProperty Count) { throw 'Counts and durations cannot be negative.' }
if ($SlicesPassed -gt $SlicesTotal) { throw 'SlicesPassed cannot exceed SlicesTotal.' }
if (@($ImplementationMinutes,$SliceReviewMinutes,$FocusedVerificationMinutes,$IntegrationReviewMinutes,$FinalGateMinutes,$PostGateReviewMinutes,$TotalMinutes) | Where-Object { $_ -lt 0 } | Measure-Object | Select-Object -ExpandProperty Count) { throw 'Counts and durations cannot be negative.' }
try { $given = $SliceModels | ConvertFrom-Json } catch { throw 'SliceModels must be valid JSON.' }
if ($Repo) {
    $sep = [char]0x1f; $end = [char]0x1e
    # The trailer holds the repo-relative path with forward slashes; accept backslashes or an absolute -Plan.
    $repoFull = [IO.Path]::GetFullPath($Repo).TrimEnd('\', '/')
    $planKey = $Plan
    if ([IO.Path]::IsPathRooted($planKey)) {
        $planFull = [IO.Path]::GetFullPath($planKey)
        if ($planFull.StartsWith($repoFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { $planKey = $planFull.Substring($repoFull.Length + 1) }
    }
    $planKey = ($planKey -replace '\\', '/') -replace '^\./', ''
    $log = $null
    try {
        $log = & git -C $Repo log --fixed-strings "--grep=Execute-Plan: $planKey" '--format=%h%x1f%B%x1e' HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { $log = $null; Write-Warning "git log failed in $Repo; slice_models kept as given." }
    } catch { $log = $null; Write-Warning "git log failed in ${Repo}: $_; slice_models kept as given." }
    $merged = [ordered]@{}
    if ($given) { foreach ($p in $given.PSObject.Properties) { $merged[$p.Name] = $p.Value } }
    $found = 0
    foreach ($rec in (($log -join "`n") -split $end)) {
        if (-not $rec.Trim()) { continue }
        $sha, $body = $rec.Trim("`n").Split($sep, 2)
        $tr = @{}
        foreach ($m in [regex]::Matches($body, '(?m)^(Execute-[A-Za-z]+):[ \t]*(.+?)[ \t]*$')) { $tr[$m.Groups[1].Value] = $m.Groups[2].Value }
        if ($tr['Execute-Plan'] -ne $planKey -or -not $tr['Execute-Slice'] -or -not $tr['Execute-Model']) { continue }
        $slice = $tr['Execute-Slice']
        # git log is newest first: the latest commit of a slice wins.
        if ($merged.Contains($slice) -and $merged[$slice] -is [hashtable]) { continue }
        $model = $tr['Execute-Model']; $effort = ''
        if ($model -match '^(.+?)\s*\(([^)]+)\)\s*$') { $model = $Matches[1]; $effort = $Matches[2] }
        $entry = @{ model = $model; host = [string]$tr['Execute-Host']; commit = $sha }
        if ($effort) { $entry.effort = $effort }
        $merged[$slice] = $entry
        $found++
    }
    if ($found -eq 0 -and $null -ne $log) { Write-Warning "No slice commit with Execute-Plan: $planKey on HEAD of $Repo; slice_models kept as given." }
    $SliceModels = ConvertTo-Json -InputObject $merged -Compress -Depth 4
}
foreach ($tokenValue in @($InputTokens,$OutputTokens)) { if ($tokenValue -and $tokenValue -notmatch '^\d+$') { throw 'Token counts must be nonnegative integers or blank.' } }
$record = [pscustomobject][ordered]@{
    started_at=$StartedAt; finished_at=$FinishedAt; plan=$Plan; branch=$Branch; commit_sha=$CommitSha
    root_model=$RootModel; root_effort=$RootEffort; peak_workers=$PeakWorkers; slices_total=$SlicesTotal
    slices_passed=$SlicesPassed; correction_rounds=$CorrectionRounds
    implementation_minutes=$ImplementationMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    slice_review_minutes=$SliceReviewMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    focused_verification_minutes=$FocusedVerificationMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    integration_review_minutes=$IntegrationReviewMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    final_gate_minutes=$FinalGateMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    post_gate_review_minutes=$PostGateReviewMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    total_minutes=$TotalMinutes.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)
    gate_status=$GateStatus; gate_sha=$GateSha; tree_clean=$TreeClean; slice_models=$SliceModels
    input_tokens=$InputTokens; output_tokens=$OutputTokens
}
$fullPath = [IO.Path]::GetFullPath($Path)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullPath) | Out-Null
$csv = @($record | ConvertTo-Csv -NoTypeInformation -Delimiter ';')
if (Test-Path -LiteralPath $fullPath) {
    $existingHeader = (Get-Content -LiteralPath $fullPath -TotalCount 1 -Encoding UTF8).TrimStart([char]0xFEFF)
    if ($existingHeader -ne $header) { throw "Metrics schema mismatch at $fullPath" }
    $line = $csv[1] + "`r`n"
} else {
    $line = $header + "`r`n" + $csv[1] + "`r`n"
}
[IO.File]::AppendAllText($fullPath,$line,[Text.UTF8Encoding]::new($false))
Write-Output $fullPath
