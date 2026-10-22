[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureRoot=Join-Path $PSScriptRoot 'fixtures/execute-resolver'
$resolver=Join-Path $root 'skills/my-execute/scripts/resolve-plan.ps1'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) "execute-resolver-$([Guid]::NewGuid().ToString('N'))"
$plans=Join-Path $temp 'plans'; New-Item -ItemType Directory $plans -Force|Out-Null
function CopyFixture([string]$Fixture,[string]$Name){Copy-Item -LiteralPath (Join-Path $fixtureRoot $Fixture) -Destination (Join-Path $plans $Name) -Force}
function ClearPlans {Get-ChildItem -LiteralPath $plans -File | Remove-Item -Force}
function Resolve([string]$Query){try { & $resolver -WorkItemOrPlan $Query -PlanDirectory $plans -AsJson | ConvertFrom-Json } catch { Write-Host "resolver input=$Query trace=$($_.ScriptStackTrace)"; throw }}
try {
    CopyFixture 'main-active.plan.md' 'WI-3572-main.plan.md'
    CopyFixture 'old-complete.plan.md' 'WI-3572-old.plan.md'
    CopyFixture 'WI-35720.plan.md' 'WI-35720.plan.md'
    CopyFixture 'unrelated.plan.md' 'unrelated.plan.md'
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'selected' -and $r.SelectedPlan.EndsWith('WI-3572-main.plan.md')) 'Did not select the only exact WI match with unfinished slices'
    Require ($r.Candidates.Count -eq 2) 'Incidental cross-reference, non-leading heading, or 35720 was treated as an exact WI match'
    $main=@($r.Candidates | Where-Object Name -eq 'WI-3572-main.plan.md')[0]
    Require ($main.GatePendingCount -eq 1 -and $main.ImplementationPendingCount -eq 1) 'Implementation work and gate todo were not classified separately'

    CopyFixture 'correction-pending.plan.md' 'WI-3572-correction.plan.md'
    $r=Resolve 'WI-3572'
    Require ($r.Outcome -eq 'ambiguous' -and -not $r.SelectedPlan) 'Multiple unfinished plans did not require an explicit choice'

    CopyFixture 'next-depends-main.plan.md' 'WI-3572-next.plan.md'
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'selected' -and $r.SelectedPlan.EndsWith('WI-3572-main.plan.md')) 'Unique explicit dependency predecessor was not selected'

    ClearPlans
    CopyFixture 'main-active.plan.md' 'WI-3572-main.plan.md'
    CopyFixture 'correction-pending.plan.md' 'WI-3572-correction.plan.md'
    # Explicit order resolves only when every active candidate has a unique order.
    $text=Get-Content -Raw (Join-Path $plans 'WI-3572-main.plan.md')
    $text=$text.Replace('work_item: 3572',"work_item: 3572`nexecution_order: 1")
    Set-Content -LiteralPath (Join-Path $plans 'WI-3572-main.plan.md') -Value $text -NoNewline
    $text=Get-Content -Raw (Join-Path $plans 'WI-3572-correction.plan.md')
    $text=$text.Replace('work_item: 3572',"work_item: 3572`nexecution_order: 2")
    Set-Content -LiteralPath (Join-Path $plans 'WI-3572-correction.plan.md') -Value $text -NoNewline
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'selected' -and $r.SelectedPlan.EndsWith('WI-3572-main.plan.md')) 'Unique explicit execution order was not honored'

    ClearPlans
    CopyFixture 'main-gate-pending.plan.md' 'WI-3572-main.plan.md'
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'needs_evidence_review' -and $r.Candidates[0].ImplementationPendingCount -eq 0) 'Gate-only pending state was not routed to external evidence review'
    CopyFixture 'old-complete.plan.md' 'WI-3572-old.plan.md'
    Require ((Resolve '3572').Outcome -eq 'ambiguous') 'Multiple gate-only/completed candidates did not require explicit selection'

    ClearPlans
    CopyFixture 'main-complete.plan.md' 'WI-3572-main.plan.md'
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'needs_evidence_review') 'Completed metadata was treated as proof without exact external evidence review'
    $explicit=Resolve (Join-Path $plans 'WI-3572-main.plan.md')
    Require ($explicit.Outcome -eq 'explicit' -and $explicit.Candidates[0].Progress -eq 'complete' -and $explicit.Candidates[0].ImplementationPendingCount -eq 0) 'Explicit path did not preserve completed native status for evidence review'

    ClearPlans
    CopyFixture 'checklist.plan.md' 'WI-3572-checklist.plan.md'
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'selected' -and $r.Candidates[0].ImplementationPendingCount -eq 1) 'Body checklist fallback did not identify pending implementation'
    ClearPlans
    CopyFixture 'unknown-status.plan.md' 'WI-3572-unknown.plan.md'
    $r=Resolve '3572'
    Require ($r.Outcome -eq 'needs_status_review') 'Unsupported native status did not fail conservatively'
    Write-Host 'Execute resolver focused tests passed.'
} finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force} }
