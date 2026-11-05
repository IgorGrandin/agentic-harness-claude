[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Presence of the key phrases that carry the execute-ig obligations (AC6, AC7, AC9).
# If a phrase is reworded on purpose, update it here in the same change.
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$skill=[IO.File]::ReadAllText((Join-Path $root 'skills/execute-ig/SKILL.md'),[Text.Encoding]::UTF8) -replace "`r`n","`n"
# Non-ASCII as code points: Windows PowerShell reads a BOM-less script as ANSI.
$afirmacoes="Afirma$([char]0xE7)$([char]0xF5)es"
$decisao="Decis$([char]0xE3)o"
$phrases=[ordered]@{
    'AC6 stop after each slice commit'      = '**Stop after the slice commit.**'
    'AC6 new session per slice'             = 'open a new session and run `/execute-ig <WI>`'
    'AC6 one session, one slice'            = '**One session, one slice.**'
    'AC6 load table by step'                = '## Load by step'
    'AC6 resumed session loads one slice'   = 'only the pending slice''s section'
    'AC6 resume keeps the Run base'         = 'resumes through the Run base (step 0)'
    'AC6 preflight only on a plan delta'    = 'run it again only when the plan changed since the last slice commit'
    'AC6 base question once per execution'  = 'asked once per execution of the WI'
    'AC7 no declared gap'                   = '**no declared gap remains.**'
    'AC7 gap becomes decision or test'      = 'a decision of the dev'
    'AC8 check before the commit'           = 'scripts/check-slice-commit.ps1'') -PlanPath <plan> -MessageFile <draft>'
    'AC8 recheck after the commit'          = 'with `-Commit <sha>`'
    'AC8 commit from the checked draft'     = 'git commit -F <draft>'
    'AC8 claims section'                    = "an ``$($afirmacoes):`` section"
    'AC8 proof per claim'                   = "``$([char]0x2014) prova: <test|grep|command>``"
    'AC8 no claims'                         = "``$($afirmacoes): nenhuma``"
    'AC8 exempt decision line'              = "``$($decisao) D<n>:`` line"
    'AC9 probe fixtures before editing'     = '**before the first edit, probe what the slice stands on.**'
    'AC9 stop when the plan contradicts'    = 'If the plan contradicts what you find'
    'AC9 neighbor Integration tests'        = '**Integration of the touched area.**'
    'AC9 baseline in a temporary worktree'  = 'in a temporary worktree'
    'AC9 UNVERIFIED without Docker'         = 'Without Docker, record `UNVERIFIED`'
    'AC9 invariant 1 is a focused check'    = 'A focused check is not the gate; the whole project and `run-gate.ps1` stay forbidden.'
}
$missing=@($phrases.GetEnumerator() | Where-Object { -not $skill.Contains($_.Value) } | ForEach-Object { "$($_.Key): $($_.Value)" })
if($missing.Count){ throw "execute-ig SKILL.md lost obligation phrases:`n$($missing -join "`n")" }
# The old limit on invariant 1 must be gone: it forbade running neighbor Integration tests.
if($skill.Contains('only focused checks run: the tests the slice adds or changes, scoped')){ throw 'Invariant 1 still restricts focused checks to the tests the slice adds or changes.' }
Write-Host 'execute-ig obligation phrases present.'
