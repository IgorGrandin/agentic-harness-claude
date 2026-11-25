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

    # -Repo fills slice_models from the slice commit trailers (host and model of another host)
    $repo=Join-Path $temp 'repo'
    New-Item -ItemType Directory $repo -Force | Out-Null
    git -C $repo init -q
    git -C $repo config user.email t@t; git -C $repo config user.name t
    $plan='.cursor/plans/wi_1_x.plan.md'
    function Slice([string]$id,[string]$hostName,[string]$model){
        $msg="feat: $id`n`nExecute-Plan: $plan`nExecute-Base: abc`nExecute-Slice: $id`nExecute-Host: $hostName`nExecute-Model: $model`nExecute-Started: 2026-11-24T10:00:00-03:00"
        git -C $repo commit -q --allow-empty -m $msg
    }
    Slice 'F1' 'antigravity' 'Gemini 4 Neon (Medium)'
    Slice 'F2' 'claude' 'claude-sonnet-5-5'
    Slice 'F1' 'antigravity' 'Gemini 4 Hydrogen (Medium)'
    git -C $repo commit -q --allow-empty -m "fix: other plan`n`nExecute-Plan: .cursor/plans/other.plan.md`nExecute-Slice: X1`nExecute-Host: codex`nExecute-Model: gpt"
    $csv2=Join-Path $temp 'r2.csv'
    $b2=$base.Clone(); $b2.Plan=$plan; $b2.Path=$csv2
    & $script @b2 -GateStatus NOT_RUN -Repo $repo -SliceModels '{"F1":{"model":"unknown","effort":"unknown"},"G9":{"model":"sonnet"}}' | Out-Null
    $row=(Import-Csv -LiteralPath $csv2 -Delimiter ';')[0]
    $sm=$row.slice_models | ConvertFrom-Json
    Require ($sm.F1.model -eq 'Gemini 4 Hydrogen' -and $sm.F1.effort -eq 'Medium' -and $sm.F1.host -eq 'antigravity') "Latest F1 trailer not recorded: $($row.slice_models)"
    Require ($sm.F2.model -eq 'claude-sonnet-5-5' -and $sm.F2.host -eq 'claude' -and -not ($sm.F2.PSObject.Properties.Name -contains 'effort')) "F2 not recorded: $($row.slice_models)"
    Require ($sm.G9.model -eq 'sonnet') 'A given slice without a commit was dropped'
    Require (-not ($sm.PSObject.Properties.Name -contains 'X1')) 'A slice of another plan was recorded'
    Require ($sm.F1.commit -match '^[0-9a-f]{7,}$') 'Commit SHA missing'

    # A plan sharing the prefix is excluded by the exact check; -Plan with backslashes or absolute still matches
    git -C $repo commit -q --allow-empty -m "feat: v2`n`nExecute-Plan: $plan.v2`nExecute-Slice: Z9`nExecute-Host: codex`nExecute-Model: gpt"
    foreach ($variant in @(($plan -replace '/', '\'), (Join-Path $repo $plan))) {
        Remove-Item -LiteralPath $csv2
        $b3=$b2.Clone(); $b3.Plan=$variant
        & $script @b3 -GateStatus NOT_RUN -Repo $repo -SliceModels '{"F1":{"model":"unknown"}}' | Out-Null
        $sm=(Import-Csv -LiteralPath $csv2 -Delimiter ';')[0].slice_models | ConvertFrom-Json
        Require ($sm.F1.model -eq 'Gemini 4 Hydrogen') "Plan form '$variant' did not match the trailer: $($sm | ConvertTo-Json -Compress)"
        Require (-not ($sm.PSObject.Properties.Name -contains 'Z9')) 'A plan sharing the prefix was recorded'
    }

    # A git failure still writes the row with the given slice_models
    Remove-Item -LiteralPath $csv2
    & $script @b2 -GateStatus NOT_RUN -Repo (Join-Path $temp 'missing') -SliceModels '{"S1":{"model":"sonnet"}}' 3>$null | Out-Null
    Require ((Import-Csv -LiteralPath $csv2 -Delimiter ';')[0].slice_models -eq '{"S1":{"model":"sonnet"}}') 'A git failure lost the row or changed slice_models'

    $text=Get-Content -Raw -LiteralPath $script
    Require ($text -match "\.claude\\brixbroker\\execute-rodadas\.csv") 'Default metrics path is not under .claude\brixbroker'
    Write-Host 'execute metrics tests passed'
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
