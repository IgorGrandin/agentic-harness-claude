[CmdletBinding()]
param([switch]$RunTests)

# Repository contract for agentic-harness-claude. Each check names the
# acceptance criterion of docs/plans/claude-harness.plan.md it enforces.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [Collections.Generic.List[string]]::new()
function Fail([string]$Message) { $failures.Add($Message) }
function Read-Text([string]$Path) { Get-Content -Raw -Encoding UTF8 -LiteralPath $Path }
function Get-Frontmatter([string]$Path) {
    $match = [regex]::Match((Read-Text $Path), '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}
function Get-Field([string]$Frontmatter, [string]$Name) {
    $match = [regex]::Match($Frontmatter, "(?m)^$([regex]::Escape($Name)):\s*(.+?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim('"') }
    return $null
}

$manifest = Read-Text (Join-Path $root 'manifest.json') | ConvertFrom-Json

# Manifest matches the tree (allowlist is explicit, not discovered).
$skillDirs = @(Get-ChildItem (Join-Path $root 'skills') -Directory | ForEach-Object Name)
$agentFiles = @(Get-ChildItem (Join-Path $root 'agents') -Filter '*.md' | ForEach-Object BaseName)
foreach ($name in $skillDirs) { if ($name -notin $manifest.skills) { Fail "Skill directory not in manifest: $name" } }
foreach ($name in $manifest.skills) {
    $skillFile = Join-Path $root "skills/$name/SKILL.md"
    if (-not (Test-Path $skillFile)) { Fail "Manifest skill without SKILL.md: $name"; continue }
    $fm = Get-Frontmatter $skillFile
    if (-not $fm -or (Get-Field $fm 'name') -ne $name) { Fail "SKILL.md name does not match directory: $name" }
}
foreach ($name in $agentFiles) { if ($name -notin $manifest.agents) { Fail "Agent file not in manifest: $name" } }

# AC1 - no Codex mechanics in Markdown instructions. Historical prose that
# merely names Codex is allowed; invocation syntax and Codex paths are not.
$forbidden = @(
    '\$(plan-task|plan-for-cursor|execute|revise|spec-task|change-task|audit-task|review-pr|grilling|handoff|takeover|brainstorming)\b',
    '\.codex\b', '\.agents[\\/]', 'openai\.yaml', '\bLuna\b', '\bSol\b', 'single-kernel',
    'diff-evidence', 'codex-handoffs', 'Codex interface', 'blocking runner', 'agentic-run'
)
$markdown = @(Get-ChildItem $root -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '[\\/](docs|tests)[\\/]' -and $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($file in $markdown) {
    $text = Read-Text $file.FullName
    foreach ($pattern in $forbidden) {
        if ($text -match $pattern) { Fail "AC1: '$pattern' in $($file.FullName.Substring($root.Length + 1))" }
    }
}

# AC2 - workflow skills keep manual-only invocation and their argument hints.
$manualOnly = @('audit-task', 'change-task', 'my-execute', 'handoff', 'plan-task', 'review-pr', 'revise', 'spec-task', 'takeover')
foreach ($name in $manualOnly) {
    $fm = Get-Frontmatter (Join-Path $root "skills/$name/SKILL.md")
    if ((Get-Field $fm 'disable-model-invocation') -ne 'true') { Fail "AC2: $name lost disable-model-invocation" }
    if (-not (Get-Field $fm 'argument-hint')) { Fail "AC2: $name lost argument-hint" }
}

# AC4 - agent model, effort and restrictions.
$expectedAgents = @{
    scout                = @{ model = 'haiku';  effort = 'low';    tools = 'Read, Grep, Glob, Bash' }
    implementer          = @{ model = 'haiku';  effort = 'high';   disallow = @('Agent') }
    reviewer             = @{ model = 'sonnet'; effort = 'medium';  disallow = @('Edit', 'Write', 'NotebookEdit', 'Agent') }
    verifier             = @{ model = 'haiku';  effort = 'high';   disallow = @('Edit', 'Write', 'NotebookEdit', 'Agent') }
    architect_escalation = @{ model = 'opus';   effort = 'high';   disallow = @('Edit', 'Write', 'NotebookEdit') }
}
foreach ($name in $expectedAgents.Keys) {
    $path = Join-Path $root "agents/$name.md"
    if (-not (Test-Path $path)) { Fail "AC4: missing agent $name"; continue }
    $fm = Get-Frontmatter $path
    $want = $expectedAgents[$name]
    if ((Get-Field $fm 'name') -ne $name) { Fail "AC4: $name has wrong name field" }
    if ((Get-Field $fm 'model') -ne $want.model) { Fail "AC4: $name model is not $($want.model)" }
    if ((Get-Field $fm 'effort') -ne $want.effort) { Fail "AC4: $name effort is not $($want.effort)" }
    if ($want.ContainsKey('tools') -and (Get-Field $fm 'tools') -ne $want.tools) { Fail "AC4: $name tools are not '$($want.tools)'" }
    if ($want.ContainsKey('disallow')) {
        $actual = @((Get-Field $fm 'disallowedTools') -split ',\s*')
        foreach ($tool in $want.disallow) { if ($tool -notin $actual) { Fail "AC4: $name does not disallow $tool" } }
    }
    if ((Read-Text $path) -match '(?im)^model:\s*fable') { Fail "AC4: $name uses Fable, which is forbidden" }
}

# AC5 - lean global instructions with the single delegation policy.
$claude = Read-Text (Join-Path $root $manifest.instructions)
$words = @($claude -split '\s+' | Where-Object { $_ }).Count
if ($words -gt 600) { Fail "AC5: CLAUDE.md has $words words (limit 600)" }
$rules = [regex]::Matches($claude, '(?m)^[1-7]\. ').Count
if ($rules -ne 7) { Fail "AC5: CLAUDE.md has $rules numbered delegation rules (expected 7)" }
foreach ($term in @('Codex', 'kernel', 'runner', 'require_escalated')) {
    if ($claude -match "(?i)\b$term\b") { Fail "AC5: CLAUDE.md mentions '$term'" }
}

# AC7 - the coverage contract has one source.
# ASCII-only anchors: Windows PowerShell 5.1 reads this BOM-less script as ANSI.
$anchor = 'para aumentar a contagem de fatias'
$holders = @(Get-ChildItem (Join-Path $root 'skills') -Recurse -File -Filter '*.md' | Where-Object { (Read-Text $_.FullName).Contains($anchor) })
if ($holders.Count -ne 1) { Fail "AC7: coverage-contract anchor found in $($holders.Count) files (expected 1)" }

# The decision record has one source; the skills that record decisions point to it.
$decisionsPath = Join-Path $root 'skills/plan-task/references/decisions.md'
if (-not (Test-Path $decisionsPath)) { Fail 'Missing decision record skills/plan-task/references/decisions.md' }
else {
    $decisionsText = Read-Text $decisionsPath
    # Each recorded decision must be self-explanatory: the record keeps the per-decision block fields.
    foreach ($field in @('**Problema:**', '**Motivo:**', '**Incertezas:**', ' do dev')) {
        if (-not $decisionsText.Contains($field)) { Fail "Decision record lost '$field'" }
    }
}
foreach ($name in @('plan-task', 'spec-task', 'change-task', 'my-execute')) {
    if (-not (Read-Text (Join-Path $root "skills/$name/SKILL.md")).Contains('decisions.md')) { Fail "$name does not reference the decision record" }
}
# The dev makes every decision: no owner-approval machinery may come back into skill instructions.
foreach ($file in Get-ChildItem (Join-Path $root 'skills') -Recurse -File -Filter '*.md') {
    $text = Read-Text $file.FullName
    foreach ($pattern in @('pendente do owner', 'aprovado pelo usu', 'owner-approval', 'classe owner', 'owner-class')) {
        if ($text.Contains($pattern)) { Fail "Owner-approval leftover '$pattern' in $($file.FullName.Substring($root.Length + 1))" }
    }
}
# /execute consults decisions in the Work Item and reads the gate's result field.
$executeText = Read-Text (Join-Path $root 'skills/my-execute/SKILL.md')
if (-not $executeText.Contains('in the Work Item itself')) { Fail '/execute does not consult decisions in the Work Item' }
if (-not $executeText.Contains('### Decisions during execution')) { Fail '/execute lacks the mid-run decision step' }
if (-not $executeText.Contains('`result` is `GREEN`')) { Fail '/execute does not read the gate manifest result field' }

# Relative Markdown links resolve, and none climbs out of the skill tree.
foreach ($file in Get-ChildItem (Join-Path $root 'skills'), (Join-Path $root 'agents') -Recurse -File -Filter '*.md') {
    foreach ($m in [regex]::Matches((Read-Text $file.FullName), '\]\(([^)#\s]+)\)')) {
        $link = $m.Groups[1].Value
        if ($link -match '^(https?|mailto):') { continue }
        if ($link -match '^\.\./\.\./') { Fail "Link escapes the skill tree: $link in $($file.Name)" }
        elseif (-not (Test-Path (Join-Path $file.DirectoryName $link))) { Fail "Dead link: $link in $($file.FullName.Substring($root.Length + 1))" }
    }
}

if ($RunTests) {
    foreach ($test in Get-ChildItem (Join-Path $root 'tests') -Filter 'test-*.ps1') {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $test.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { Fail "Test failed: $($test.Name) - $(($output | Select-Object -Last 3) -join ' | ')" }
        else { Write-Host "PASS $($test.Name)" }
    }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    throw "Verification failed: $($failures.Count) problem(s)"
}
Write-Host "Verification passed: $(@($manifest.skills).Count) skills, $(@($manifest.agents).Count) agents, CLAUDE.md $words words"
