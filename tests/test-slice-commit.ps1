[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$check=Join-Path $root 'skills/execute-ig/scripts/check-slice-commit.ps1'
$fx=Join-Path $PSScriptRoot 'fixtures/slice-commit'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) "slice-commit-$([Guid]::NewGuid().ToString('N'))"
$repo=Join-Path $temp 'repo'
function G { $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'; try { $out=& git -C $repo @args 2>&1; if($LASTEXITCODE -ne 0){throw "git $args failed: $out"}; $out } finally { $ErrorActionPreference=$previous } }
function Run-Msg([string]$Message,[string]$Plan='with-disc.plan.md'){
    $planPath=Join-Path $fx $Plan
    $msgPath=if([IO.Path]::IsPathRooted($Message)){$Message}else{Join-Path $fx $Message}
    $out=& powershell -NoProfile -ExecutionPolicy Bypass -File $check -RepoRoot $root -PlanPath $planPath -MessageFile $msgPath -AsJson
    [pscustomobject]@{Exit=$LASTEXITCODE; Result=(($out -join "`n") | ConvertFrom-Json)}
}
function Run-Commit([string]$Sha,[string]$Plan='with-disc.plan.md'){
    $out=& powershell -NoProfile -ExecutionPolicy Bypass -File $check -RepoRoot $repo -PlanPath (Join-Path $fx $Plan) -Commit $Sha -AsJson
    [pscustomobject]@{Exit=$LASTEXITCODE; Result=(($out -join "`n") | ConvertFrom-Json)}
}
function Has($Result,[int]$Item,[string]$Severity,[string]$MessageLike){ @($Result.Findings | Where-Object { $_.Item -eq $Item -and $_.Severity -eq $Severity -and $_.Message -like $MessageLike }).Count -gt 0 }
function Show($r){ ($r.Result.Findings | ConvertTo-Json -Compress) }
try {
    # Exempt and clean cases: the same engine returns 0.
    $r=Run-Msg 'clean.msg'
    Require ($r.Exit -eq 0 -and $r.Result.Status -eq 'CLEAN') "Clean body did not pass (also: 'todo' and 'dependente' are not gap markers): exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'exempt-decision.msg'
    Require ($r.Exit -eq 0) "Gap marker inside a Decisao D<n>: line was blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'exempt-pending.msg'
    Require ($r.Exit -eq 0) "Pending slices listed under Fatias pendentes: were blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'claims-none.msg' 'no-disc.plan.md'
    Require ($r.Exit -eq 0) "Plan without an elected discriminant demanded a [visto]: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'claims-none-with-visto.msg'
    Require ($r.Exit -eq 0) "'Afirmacoes: nenhuma' with the [visto] did not pass: exit $($r.Exit) $(Show $r)"

    # Real trailers carry the frontmatter todo id; the heading is "### F6 - ..." (BrixBroker plans).
    $r=Run-Msg 'todo-id-visto.msg' 'todo-id.plan.md'
    Require ($r.Exit -eq 0) "Slice named by todo id did not resolve to its heading: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'todo-id-no-visto.msg' 'todo-id.plan.md'
    Require ($r.Exit -eq 1 -and (Has $r.Result 3 'BLOCK' '*ModuloTests.CasoZ*')) "Discriminant of a slice named by todo id was not enforced: exit $($r.Exit) $(Show $r)"

    # Plans whose headings are "### S6 - ..." and whose trailer is "S6".
    $r=Run-Msg 's-heading-visto.msg' 's-heading.plan.md'
    Require ($r.Exit -eq 0) "Slice S<n> did not resolve to a '### S<n>' heading: exit $($r.Exit) $(Show $r)"

    # Violations, one per condition.
    $r=Run-Msg 'no-plan-trailer.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 1 'BLOCK' '*Execute-Plan*')) "Missing Execute-Plan not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'no-base-trailer.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 1 'BLOCK' '*Execute-Base*')) "Missing Execute-Base not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'no-slice-trailer.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 1 'BLOCK' '*Execute-Slice*')) "Missing Execute-Slice not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'no-claims.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 2 'BLOCK' 'No "Afirma*')) "Missing Afirmacoes: section not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'claim-no-proof.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 2 'BLOCK' '*without "prova:"*sempre*')) "Claim without prova: not blocked: exit $($r.Exit) $(Show $r)"
    Require (@($r.Result.Findings | Where-Object Item -eq 2).Count -eq 1) 'The claim that has prova: was blocked too'
    $r=Run-Msg 'no-visto.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 3 'BLOCK' '*FooTests.CasoX*')) "Missing [visto] of the elected discriminant not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'visto-other-line.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 3 'BLOCK' '*FooTests.CasoX*')) "[visto] on another line satisfied the discriminant: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'gap-marker.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 4 'BLOCK' '*lacuna*')) "Gap marker outside an exempt line not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'gap-todo.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 4 'BLOCK' '*TODO*')) "TODO not blocked: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'gap-in-claims.msg'
    Require ($r.Exit -eq 1 -and (Has $r.Result 4 'BLOCK' '*fica para*')) "Gap marker inside the claims section not blocked: exit $($r.Exit) $(Show $r)"

    # Unreadable inputs.
    $r=Run-Msg 'clean.msg' 'missing.plan.md'
    Require ($r.Exit -eq 2 -and (Has $r.Result 0 'UNVERIFIED' '*Plan not found*')) "Missing plan did not yield UNVERIFIED: exit $($r.Exit) $(Show $r)"
    $r=Run-Msg 'missing.msg'
    Require ($r.Exit -eq 2 -and (Has $r.Result 0 'UNVERIFIED' '*Message file not found*')) "Missing message did not yield UNVERIFIED: exit $($r.Exit) $(Show $r)"

    # -Commit reads git log -1; the Execute-* trailers decide whether the commit is a slice commit.
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    G init -q -b master; G config user.name t; G config user.email t@t; G config core.autocrlf false
    [IO.File]::WriteAllText((Join-Path $repo 'a.txt'),"a`n")
    G add -A
    function Commit-From([string]$Msg){ [IO.File]::WriteAllText((Join-Path $repo 'a.txt'),"$([Guid]::NewGuid())`n"); G add -A; G commit -q -F (Join-Path $fx $Msg); (G rev-parse HEAD).Trim() }
    $sha=Commit-From 'fix-commit.msg'
    $r=Run-Commit $sha
    Require ($r.Exit -eq 0) "A commit without any Execute-* trailer was not ignored: exit $($r.Exit) $(Show $r)"
    $sha=Commit-From 'clean.msg'
    $r=Run-Commit $sha
    Require ($r.Exit -eq 0) "Clean slice commit failed the -Commit recheck: exit $($r.Exit) $(Show $r)"
    $sha=Commit-From 'gap-marker.msg'
    $r=Run-Commit $sha
    Require ($r.Exit -eq 1 -and (Has $r.Result 4 'BLOCK' '*lacuna*')) "Violating slice commit passed the -Commit recheck: exit $($r.Exit) $(Show $r)"
    $sha=Commit-From 'no-slice-trailer.msg'
    $r=Run-Commit $sha
    Require ($r.Exit -eq 1 -and (Has $r.Result 1 'BLOCK' '*Execute-Slice*')) "Commit with some but not all trailers was ignored: exit $($r.Exit) $(Show $r)"
    $r=Run-Commit ('0'*40)
    Require ($r.Exit -eq 2) "Unknown commit did not yield UNVERIFIED: exit $($r.Exit) $(Show $r)"

    Write-Host 'Slice commit check focused tests passed.'
} finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force} }
