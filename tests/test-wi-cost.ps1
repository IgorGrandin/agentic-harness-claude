[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script=Join-Path $root 'scripts/report-wi-cost.ps1'
$fx=Join-Path $PSScriptRoot 'fixtures/wi-cost'
$tokens=Join-Path $fx 'tokens-by-model.csv'
$rounds=Join-Path $fx 'execute-rodadas.csv'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Near([double]$a,[double]$b){[math]::Abs($a-$b) -lt 0.00001}

$json=& $script -TokensPath $tokens -RoundsPath $rounds -AsJson | Out-String
$rows=@(($json | ConvertFrom-Json) | ForEach-Object { $_ })  # PS 5.1 devolve o array JSON como um unico objeto
function Row([string]$wi){$r=@($rows | Where-Object { $_.work_item -eq $wi }); Require ($r.Count -eq 1) "Expected exactly one row for WI '$wi', got $($r.Count)"; $r[0]}
function Avg($row,[string]$role,[string]$model){$g=@($row.by_role_model | Where-Object { $_.role -eq $role -and $_.model -eq $model }); Require ($g.Count -eq 1) "Missing $role/$model for WI $($row.work_item)"; [double]$g[0].avg_prompt_per_turn}

# WI A (3001): dois modelos, papeis main e sub, dois planos distintos
$a=Row '3001'
Require (Near $a.cost_usd 5.75) "WI 3001 cost should sum both models (5.75), got $($a.cost_usd)"
Require ($a.sessions -eq 2) "WI 3001 sessions should be 2, got $($a.sessions)"
Require ($a.plans -eq 2) "WI 3001 plans should be 2 (not 3; no-WI plan excluded; same plan with/without path and .plan.md counted once), got $($a.plans)"
Require ($a.by_role_model.Count -eq 4) "WI 3001 should keep 4 role x model groups, got $($a.by_role_model.Count)"
Require ((Avg $a 'main' 'claude-haiku-5-5') -eq 100) 'main/haiku avg prompt should be 1000/10'
Require ((Avg $a 'sub' 'claude-haiku-5-5') -eq 100) 'sub/haiku avg prompt should be 500/5'
Require ((Avg $a 'main' 'claude-sonnet-5-5') -eq 400) 'main/sonnet avg prompt should be 4000/10'
Require ((Avg $a 'sub' 'claude-sonnet-5-5') -eq 200) 'sub/sonnet avg prompt should be 2000/10'

# Linha sem WI entra como tal, com o plano sem wi_<id>_
$n=Row '(sem WI)'
Require (Near $n.cost_usd 0.75) "No-WI cost should be 0.75, got $($n.cost_usd)"
Require ($n.sessions -eq 1) 'No-WI sessions should be 1'
Require ($n.plans -eq 1) "No-WI bucket should hold the plan without wi_<id>_, got $($n.plans)"

# WI so no tokens CSV: sem planos, sem erro
$c=Row '3003'
Require ($c.plans -eq 0 -and (Near $c.cost_usd 0.1)) 'WI only in tokens CSV should show cost and zero plans'
# WI so no rodadas CSV: custo zero, sem erro
$d=Row '3004'
Require ($d.plans -eq 1 -and $d.cost_usd -eq 0 -and $d.sessions -eq 0) 'WI only in rounds CSV should show one plan and zero cost'
# WI 3002 em ambos
$b=Row '3002'
Require ((Near $b.cost_usd 2.25) -and $b.plans -eq 1 -and $b.sessions -eq 1) 'WI 3002 mismatch'
Require ($rows.Count -eq 5) "Expected 5 rows, got $($rows.Count)"

# Saida de console: cabecalho avisa que e aproximado, e a tabela lista a WI
$text=(& $script -TokensPath $tokens -RoundsPath $rounds | Out-String)
Require ($text -match 'aproximado') 'Console output must say prompt average is approximate'
Require ($text -match '3001') 'Console output must list WI 3001'

# CSV ausente: erro claro
$threw=$false
try { & $script -TokensPath (Join-Path $fx 'nope.csv') -RoundsPath $rounds | Out-Null } catch { $threw=$true }
Require $threw 'Missing tokens CSV should throw'

Write-Host 'wi cost tests passed'
