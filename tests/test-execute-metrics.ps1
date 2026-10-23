[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script=Join-Path $root 'skills/execute-ig/scripts/append-metrics.ps1'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) "execute-metrics-$([Guid]::NewGuid().ToString('N'))"
$csv=Join-Path $temp 'execute-rodadas.csv'
$sha='a'*40
$base=@{StartedAt='2026-10-15T10:00:00-03:00';FinishedAt='2026-10-15T11:00:00-03:00';Plan='.cursor/plans/wi_3572_x.plan.md';Branch='feature/x';RootModel='sonnet';RootEffort='medium';Path=$csv}
try {
    New-Item -ItemType Directory $temp -Force | Out-Null
    & $script @base -CommitSha $sha -GateStatus PASSED -GateSha $sha -TreeClean true -SliceModels '{"S1":{"model":"sonnet","effort":"medium"}}'
    & $script @base -GateStatus NOT_RUN
    $lines=Get-Content -LiteralPath $csv
    Require ($lines[0].StartsWith('started_at;finished_at;plan;')) 'Header missing or not first'
    Require ($lines.Count -eq 3) 'Expected header plus two appended rows'
    Require (@($lines | Where-Object { $_ -like 'started_at;*' }).Count -eq 1) 'Header was written more than once'

    $rejected=$false
    try { & $script @base -CommitSha $sha -GateStatus PASSED -GateSha ('b'*40) -TreeClean true } catch { $rejected=$true }
    Require $rejected 'PASSED gate with a gate SHA different from the commit was accepted'
    $rejected=$false
    try { & $script @base -CommitSha $sha -GateStatus PASSED -GateSha $sha -TreeClean false } catch { $rejected=$true }
    Require $rejected 'PASSED gate with a dirty tree was accepted'
    Require ((Get-Content -LiteralPath $csv).Count -eq 3) 'A rejected run still appended a row'

    $text=Get-Content -Raw -LiteralPath $script
    Require ($text -match "\.claude\\brixbroker\\execute-rodadas\.csv") 'Default metrics path is not under .claude\brixbroker'
    Write-Host 'execute metrics tests passed'
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
