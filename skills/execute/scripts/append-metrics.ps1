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
try { $null = $SliceModels | ConvertFrom-Json } catch { throw 'SliceModels must be valid JSON.' }
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
