[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$check=Join-Path $root 'skills/execute-ig/scripts/check-plan.ps1'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) "check-plan-$([Guid]::NewGuid().ToString('N'))"
$repo=Join-Path $temp 'repo'
function G { $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'; try { $out=& git -C $repo @args 2>&1; if($LASTEXITCODE -ne 0){throw "git $args failed: $out"}; $out } finally { $ErrorActionPreference=$previous } }
function Put([string]$Path,[string]$Text){ $full=Join-Path $repo $Path; New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null; [IO.File]::WriteAllText($full,$Text,[Text.UTF8Encoding]::new($false)) }
function Run-Check([string]$Plan){
    $out=& powershell -NoProfile -ExecutionPolicy Bypass -File $check -RepoRoot $repo -PlanPath $Plan -AsJson
    [pscustomobject]@{Exit=$LASTEXITCODE; Result=(($out -join "`n") | ConvertFrom-Json)}
}
function Has($Result,[int]$Item,[string]$Severity,[string]$MessageLike){ @($Result.Findings | Where-Object { $_.Item -eq $Item -and $_.Severity -eq $Severity -and $_.Message -like $MessageLike }).Count -gt 0 }
# Non-ASCII as code points: Windows PowerShell reads a BOM-less script as ANSI.
# Assertions avoid non-ASCII: the child's stdout decoding depends on the calling console.
$cao="$([char]0xE7)$([char]0xE3)o"; $coes="$([char]0xE7)$([char]0xF5)es"; $a="$([char]0xE1)"; $ell="$([char]0x2026)"
$table=@"
# Verifica${coes} feitas antes de entregar este plano

| Passe | O que verifiquei | Onde |
|---|---|---|
| **Manifesto** | ok | sha |
| Encanamento | ok | - |
| **Ambiente** | ok | - |
| Testes | ok | - |
| **Projeto do teste** | ok | - |
| Gate | ok | - |
| Rules | ok | - |
| **C${a}psula** | ok | - |
| **Cobertura** | ok | - |
| **Reuso** | ok | - |
| Contradi${cao} | ok | - |
| **Erros declarados** | ok | - |
"@
function Plan([string]$Sha,[string]$Slices,[string]$Table=$table,[string]$Front=''){
@"
---
name: WI 1 x
$Front
---

## Manifesto de execu${cao}

- **SHA-base:** ``$Sha``

## Fatias

$Slices

$Table
"@
}
$good=@"
### Fatia 1 - Dom${a}nio

- Write-set: ``platform/backend/src/M/Foo.cs``, testes em ``platform/backend/tests/Insurtech.Unit.Tests/M/FooTests.cs``.
- **Discriminante da fatia:** ``FooTests`` caso X.

**Reuso:**
| Artefato do plano | Busca | Candidato | Decis${cao} |
|---|---|---|---|
| ``Foo`` | ``Foo`` | nenhum | criar novo |
"@
try {
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    G init -q -b master; G config user.name t; G config user.email t@t; G config core.autocrlf false
    Put 'platform/backend/tests/Insurtech.Unit.Tests/Keep.cs' "class Keep {}`n"
    Put 'platform/backend/tests/Insurtech.Integration.Tests/Keep.cs' "class Keep {}`n"
    G add -A; G commit -q -m base
    $sha=(G rev-parse HEAD).Trim()

    # Clean plan, accented headings and rows included.
    Put 'p/clean.plan.md' (Plan $sha $good)
    $clean=Run-Check 'p/clean.plan.md'
    Require ($clean.Exit -eq 0 -and $clean.Result.Status -eq 'CLEAN') "Clean plan did not pass: exit $($clean.Exit) $(($clean.Result.Findings | ConvertTo-Json -Compress))"

    # Item 1 - missing manifest, manifest after a slice, unknown SHA-base.
    Put 'p/nomanifest.plan.md' ((Plan $sha $good) -replace "## Manifesto de execu${cao}", '## Outro')
    $r=Run-Check 'p/nomanifest.plan.md'
    Require ($r.Exit -eq 1 -and (Has $r.Result 1 'BLOCK' 'No "## Manifesto*')) 'Item 1: missing manifest not blocked'
    $late=(Plan $sha $good) -replace "(?s)(## Manifesto de execu${cao}\s+- \*\*SHA-base:\*\* ``[0-9a-f]+``\s+)(## Fatias\s+)", '$2'
    $late=$late -replace '(?s)(\*\*Reuso:\*\*)', "## Manifesto de execu${cao}`n`n- **SHA-base:** ``$sha```n`n### Fatia 2 - y`n`n**Discriminante:** nenhum`n`n`$1"
    Put 'p/late.plan.md' $late
    $r=Run-Check 'p/late.plan.md'
    Require (Has $r.Result 1 'BLOCK' '*after the first slice*') 'Item 1: manifest after the first slice not blocked'
    Put 'p/badsha.plan.md' (Plan ('0'*40) $good)
    $r=Run-Check 'p/badsha.plan.md'
    Require ($r.Exit -eq 1 -and (Has $r.Result 1 'BLOCK' '*is not a commit*')) 'Item 1: unknown SHA-base not blocked'

    # Item 2 - abbreviated paths (three dots and the ellipsis character) and parent_plan.
    Put 'p/capsule.plan.md' (Plan $sha ($good + "`n- Also ``.../Entities/Foo.cs`` and ``platform/${ell}/Bar.cs``; not a path: ``a...b``.") -Front 'parent_plan: big.plan.md')
    $r=Run-Check 'p/capsule.plan.md'
    Require (Has $r.Result 2 'BLOCK' '*.../Entities/Foo.cs*') 'Item 2: three-dot path not blocked'
    Require (Has $r.Result 2 'BLOCK' '*platform/?/Bar.cs*') 'Item 2: ellipsis path not blocked'
    Require (-not (Has $r.Result 2 'BLOCK' '*a...b*')) 'Item 2: token without a slash was blocked'
    Require (Has $r.Result 2 'BLOCK' 'parent_plan*') 'Item 2: parent_plan not blocked'

    # Item 3 - test project that does not exist; allowed when a Reuso row creates it.
    Put 'p/project.plan.md' (Plan $sha ($good -replace 'Insurtech\.Unit\.Tests', 'Insurtech.Infrastructure.Tests'))
    $r=Run-Check 'p/project.plan.md'
    Require ($r.Exit -eq 1 -and (Has $r.Result 3 'BLOCK' 'Test project Insurtech.Infrastructure.Tests*')) 'Item 3: missing test project not blocked'
    Put 'p/newproject.plan.md' (Plan $sha (($good -replace 'Insurtech\.Unit\.Tests', 'Insurtech.Email.Tests') + "`n| projeto ``Insurtech.Email.Tests`` | ``Email`` | nenhum | criar novo |"))
    $r=Run-Check 'p/newproject.plan.md'
    Require (-not (Has $r.Result 3 'BLOCK' '*')) 'Item 3: project created in a Reuso row was blocked'
    Put 'p/bare.plan.md' (Plan $sha ($good + "`n- Gate: ``Insurtech.HostSmoke.Tests``."))
    $r=Run-Check 'p/bare.plan.md'
    Require (Has $r.Result 3 'BLOCK' 'Test project Insurtech.HostSmoke.Tests*') 'Item 3: bare project name not checked'
    Put 'p/otherpath.plan.md' (Plan $sha ($good + "`n- Fora do backend: ``platform/frontend/apps/Insurtech.Web.Tests`` e ``docs/old/Insurtech.Old.Tests``."))
    $r=Run-Check 'p/otherpath.plan.md'
    Require (-not (Has $r.Result 3 'BLOCK' '*')) 'Item 3: a name inside a non-backend path was taken as a backend project'
    Put 'p/rejected.plan.md' (Plan $sha (($good -replace 'Insurtech\.Unit\.Tests', 'Insurtech.Email.Tests') + "`n| ``Insurtech.Email.Tests`` | ``Email`` | ``Insurtech.Unit.Tests`` | reusar o existente |"))
    $r=Run-Check 'p/rejected.plan.md'
    Require (Has $r.Result 3 'BLOCK' 'Test project Insurtech.Email.Tests*') 'Item 3: a Reuso row that does not create the project excused it'

    # Item 4 - slice without Reuso, without discriminante; no slice at all.
    Put 'p/slice.plan.md' (Plan $sha "### Fatia 1 - x`n`n- Write-set: ``platform/backend/src/M/Foo.cs``.")
    $r=Run-Check 'p/slice.plan.md'
    Require (Has $r.Result 4 'BLOCK' '*no `*`*Reuso:`*`* block*') 'Item 4: slice without Reuso not blocked'
    Require (Has $r.Result 4 'BLOCK' '*names no discriminante*') 'Item 4: slice without discriminante not blocked'
    Put 'p/noslice.plan.md' (Plan $sha 'Sem fatias.')
    $r=Run-Check 'p/noslice.plan.md'
    Require ($r.Exit -eq 2 -and (Has $r.Result 4 'UNVERIFIED' '*')) "Item 4: plan without slices did not yield UNVERIFIED: exit $($r.Exit)"
    # Each slice ends at the next slice: Reuso in slice 2 does not cover slice 1.
    Put 'p/twoslices.plan.md' (Plan $sha ("### Fatia 1 - a`n`n- **Discriminante:** ``A``.`n`n" + ($good -replace 'Fatia 1', 'Fatia 2')))
    $r=Run-Check 'p/twoslices.plan.md'
    Require (Has $r.Result 4 'BLOCK' '### Fatia 1*no*Reuso*') 'Item 4: Reuso of slice 2 covered slice 1'
    Require (-not (Has $r.Result 4 'BLOCK' '### Fatia 2*')) 'Item 4: complete slice 2 was blocked'
    # A "#" comment inside a fenced block is not a heading; a fenced "## Fatia" is not a slice.
    $fence='```'
    $fencedSlice=$good -replace '(- \*\*Discriminante)', "$fence powershell`n# build primeiro`ndotnet build`n$fence`n`n$fence markdown`n## Fatia 9 - exemplo`n$fence`n`n`$1"
    Put 'p/fence.plan.md' (Plan $sha $fencedSlice)
    $r=Run-Check 'p/fence.plan.md'
    Require ($r.Exit -eq 0) "Item 4: a fenced comment or heading changed the slices: exit $($r.Exit) $(($r.Result.Findings | ConvertTo-Json -Compress))"

    # Item 5 - missing table, missing rows.
    Put 'p/notable.plan.md' (Plan $sha $good -Table '')
    $r=Run-Check 'p/notable.plan.md'
    Require (Has $r.Result 5 'BLOCK' 'No "Verificacoes*') 'Item 5: missing table not blocked'
    Put 'p/rows.plan.md' (Plan $sha $good -Table (($table -split "`n" | Where-Object { $_ -notmatch 'Projeto do teste|Erros declarados|psula' }) -join "`n"))
    $r=Run-Check 'p/rows.plan.md'
    Require (Has $r.Result 5 'BLOCK' '*"Projeto do teste"*') 'Item 5: missing Projeto do teste row not blocked'
    Require (Has $r.Result 5 'BLOCK' '*"Erros declarados"*') 'Item 5: missing Erros declarados row not blocked'
    Require (Has $r.Result 5 'BLOCK' '*"C*psula"*') 'Item 5: missing accented row not blocked'

    # Item 0 - the check itself fails.
    $r=Run-Check 'p/missing.plan.md'
    Require ($r.Exit -eq 2 -and (Has $r.Result 0 'UNVERIFIED' '*Plan not found*')) "Item 0: missing plan did not yield UNVERIFIED: exit $($r.Exit)"

    Write-Host 'Plan check focused tests passed.'
} finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force} }
