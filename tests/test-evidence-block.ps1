[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script = Join-Path $root 'skills/execute-ig/scripts/render-evidence-block.ps1'
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$temp = Join-Path ([IO.Path]::GetTempPath()) "evidence-block-$([Guid]::NewGuid().ToString('N'))"
$repo = Join-Path $temp 'repo'
function G { $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { $out = & git -C $repo @args 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $args failed: $out" }; $out } finally { $ErrorActionPreference = $previous } }
function Put([string]$Path, [string]$Text) { $full = Join-Path $repo $Path; New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null; [IO.File]::WriteAllText($full, $Text, [Text.UTF8Encoding]::new($false)) }
function Run-Block([string[]]$Extra = @()) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -RepoRoot $repo -PlanPath '.cursor/plans/wi_1_x.plan.md' @Extra
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}
try {
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    G init -q -b master; G config user.name t; G config user.email t@t; G config core.autocrlf false
    Put '.cursor/plans/wi_1_x.plan.md' "---`nname: x`n---`n## Fronteiras`n- Sanitizador -> componente de e-mail (atributos data-remote-src)`n- Dois envios concorrentes na mesma conversa`n## Fatias`n"
    G add -A; G commit -q -m base
    $base = (G rev-parse HEAD).Trim()

    # No slice commit yet: the script cannot render anything (exit 2), and says why.
    $none = Run-Block
    Require ($none.Exit -eq 2 -and $none.Text -like '*No slice commit*') "No slice commit did not exit 2: $($none.Exit) $($none.Text)"

    Put 'src/a.cs' "class A {}`n"
    G add -A
    $msg = @"
feat: fatia F1

Traceability:
- C1 (teste A): [visto] vermelho antes: saida 1. Verde depois: saida 0.
- C2 (teste B): [raciocinado] a asserção observa o atributo.

Mutante: linha removida de uma copia; teste A saiu 1.

Desvios: nenhum.

Decisão D7: a régua cria conversa só na primeira resposta; diverge do critério 12 da spec.
Decisão D8: nome do campo segue o irmão.

Afirmações:
- O envio duplicado e recusado — prova: teste A.

Execute-Plan: .cursor/plans/wi_1_x.plan.md
Execute-Base: $base
Execute-Slice: F1
"@
    $msgFile = Join-Path $temp 'msg.txt'
    [IO.File]::WriteAllText($msgFile, $msg, [Text.UTF8Encoding]::new($false))
    G commit -q -F $msgFile
    $head = (G rev-parse HEAD).Trim()

    $ok = Run-Block
    Require ($ok.Exit -eq 0) "Block did not render: exit $($ok.Exit) $($ok.Text)"
    Require ($ok.Text -like "*execute-evidence head=$head*") 'Block does not carry the HEAD marker'
    Require ($ok.Text.Contains('[visto] x1, [raciocinado] x1'))  "Label counts missing: $($ok.Text)"
    Require ($ok.Text -like '*Mutante: linha removida*') 'Mutant line missing'
    Require ($ok.Text -like '*Sanitizador -> componente de e-mail*' -and $ok.Text -like '*Dois envios concorrentes*') 'Plan boundaries not copied'
    Require ($ok.Text -like '*Gate local: manifesto não informado*') 'Missing manifest not stated'
    $div = ($ok.Text -split "\*\*Decis[^\n]*divergem[^\n]*\n")[1]
    Require ($div -like '*D7*' -and ($div -split "`n")[0] -like '*D7*' -and $div -notlike '*- Decisão D8*') "Only the diverging decision (D7) belongs under the diverging heading: $div"
    Require ($ok.Text -like '*prova: teste A*') 'Claims not copied'

    # Manifest for another HEAD: refused. For this HEAD: shown.
    $stale = Join-Path $temp 'stale.json'
    @{ status = 'VALID'; result = 'GREEN'; HEAD = ('0' * 40) } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $stale
    $r = Run-Block @('-GateManifest', $stale)
    Require ($r.Exit -eq 1 -and $r.Text -like 'REFUSED: the gate manifest is for*') "Stale manifest was not refused: $($r.Exit) $($r.Text)"
    $fresh = Join-Path $temp 'fresh.json'
    @{ status = 'VALID'; result = 'GREEN'; HEAD = $head; gateTreeFingerprint = 'abc123' } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $fresh
    $r = Run-Block @('-GateManifest', $fresh)
    Require ($r.Exit -eq 0 -and $r.Text.Contains('result `GREEN`, fingerprint `abc123`')) "Fresh manifest not rendered: $($r.Exit) $($r.Text)"

    # Dirty tree: refused.
    Put 'src/b.cs' "class B {}`n"
    $r = Run-Block
    Require ($r.Exit -eq 1 -and $r.Text -like 'REFUSED: the tree is not clean*') "Dirty tree was not refused: $($r.Exit) $($r.Text)"

    Write-Host 'Evidence block focused tests passed.'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
