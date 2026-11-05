[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

# Presence tests for the plan obligations (AC10, AC11, AC12): the key phrases must stay in the
# skills, and the phrases they replaced must not come back. The script is ASCII (Windows
# PowerShell reads a BOM-less script as ANSI), so each accented letter in a pattern is a
# single-character wildcard ".".
function Read-Skill([string]$Name) { ([IO.File]::ReadAllText((Join-Path $root "skills/$Name/SKILL.md"), [Text.Encoding]::UTF8)) -replace "`r`n", "`n" }
$failures = [Collections.Generic.List[string]]::new()
function Present([string]$Skill, [string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -notmatch $Pattern) { $failures.Add("$Skill must contain: $Label") }
}
function Absent([string]$Skill, [string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -match $Pattern) { $failures.Add("$Skill must NOT contain: $Label") }
}

$revise = Read-Skill 'revise'
$review = Read-Skill 'review-pr'
$planFor = Read-Skill 'plan-for-cursor'

# AC12 - /revise section 4: anchoring, check-plan, convergence.
$section4 = [regex]::Match($revise, '(?s)## 4\. Se corre..o for necess.ria(.*?)\n## 5\.').Groups[1].Value
if (-not $section4) { $failures.Add('revise: section "## 4. Se correcao for necessaria" not found') }
Present 'revise s4' $section4 'plan-task` .3' 'the plan-task section 3 anchoring step'
Present 'revise s4' $section4 'check-plan\.ps1' 'the check-plan.ps1 run before delivering'
Present 'revise s4' $section4 'ADR/Rules' 'the ADR/Rules row fed by the anchoring'
Present 'revise s4' $section4 'S. achado \*\*bloqueante\*\*, ou n.o bloqueante que o dev mandar corrigir, vira item do plano de corre..o' 'only blocking findings (or those the dev orders fixed) become plan items'
Present 'revise s4' $section4 'Res.duos e decis.es' 'the rest goes to the "Residuos e decisoes" table'
Absent 'revise' $revise 'Todo achado vira item da lista do plano de corre..o' 'the old sentence "Todo achado vira item da lista do plano de correcao"'
Absent 'revise' $revise 'ao fechar a rodada\*\* \(passo 5\)' 'the "(passo 5)" pointer to the residue table (it must name the table)'
Present 'revise' $revise 'tabela "Res.duos e decis.es" do build-log ao fechar a rodada' 'the residue table pointed to by name'

# AC12 - /review-pr: the correction plan runs check-plan.ps1 and carries only blocking findings.
$planLine = [regex]::Match($review, '(?m)^- \*\*Plano de corre..o\*\*.*$').Value
if (-not $planLine) { $failures.Add('review-pr: bullet "Plano de correcao" not found') }
Present 'review-pr plan bullet' $planLine 'check-plan\.ps1' 'the check-plan.ps1 run'
Present 'review-pr plan bullet' $planLine 'bloqueantes' 'only blocking findings go into the plan'
Present 'review-pr plan bullet' $planLine 'dev mandar corrigir' 'non-blocking findings the dev orders fixed'
Present 'review-pr' $review 'Res.duo decidido n.o . achado' 'the "Residuo decidido nao e achado" section (kept)'

# AC10 - plan-for-cursor pass 6 renamed, row renamed, still twelve passes.
Present 'plan-for-cursor' $planFor '(?m)^### 6\. ADRs e rules da .rea$' 'pass 6 titled "ADRs e rules da area"'
Absent 'plan-for-cursor' $planFor 'As rules da .rea, despachadas pela' 'the old pass 6 title'
Present 'plan-for-cursor' $planFor '(?m)^\| \*\*ADR/Rules\*\* \|' 'the ADR/Rules row in the verification table'
Absent 'plan-for-cursor' $planFor '(?m)^\| Rules \|' 'the old "Rules" row in the verification table'
Present 'plan-for-cursor' $planFor 'Os doze passes' 'the "doze passes" heading'
$passes = @([regex]::Matches($planFor, '(?m)^### \d+\. ')).Count
if ($passes -ne 12) { $failures.Add("plan-for-cursor must have 12 numbered passes, found $passes") }
Present 'plan-for-cursor' $planFor 'inclusive os planos de corre..o do `/revise` e do `/review-pr`' 'pass 6 applies to correction plans too'

# AC11 - plan-for-cursor pass 4(h): production composition.
Present 'plan-for-cursor' $planFor '\*\*\(h\) Composi..o de produ..o' 'pass 4(h), composition of production'
Present 'plan-for-cursor' $planFor '`Composi..o:`' 'the Composicao: line'
Present 'plan-for-cursor' $planFor 'Integration ou HostSmoke' 'the Integration / HostSmoke trigger'

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    throw "Plan obligations: $($failures.Count) check(s) failed."
}
Write-Host 'Plan obligations presence tests passed.'
