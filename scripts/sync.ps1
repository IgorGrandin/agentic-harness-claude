[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('codex', 'antigravity')]
    [string[]]$Hosts = @('codex', 'antigravity'),
    [string]$CodexHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'),
    [string]$GeminiHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gemini'),
    [switch]$PurgeLegacyHomes
)

# Generates the Codex and Antigravity global config from this repo's single source:
#   CLAUDE.md (rules), agents/*.md (role bodies), skills/** (workflows),
#   core/roles/roles.json (model/effort per host + skill equivalence adapters).
# Base skills in skills/** are NEVER edited; sync.ps1 projects them into each host
# with host-equivalence preambles, script-path rewrites, and (for Codex) $skill
# invocation rewrites + agents/openai.yaml metadata.
# Writes:
#   <CodexHome>/AGENTS.md, <CodexHome>/agents/*.toml, <CodexHome>/skills/<skill>/**
#   <GeminiHome>/GEMINI.md, <GeminiHome>/config/agents/*.md, <GeminiHome>/config/skills/<skill>/**
# Replaced or removed items are backed up first under <home>/portable-backups/<timestamp>/.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'manifest.json') | ConvertFrom-Json
$roles = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'core/roles/roles.json') | ConvertFrom-Json
if ($roles.schemaVersion -ne 1) { throw "Unsupported roles schema: $($roles.schemaVersion)" }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-MarkdownWithFrontmatter([string]$Path) {
    $text = (Get-Content -Raw -Encoding UTF8 $Path) -replace "`r`n", "`n"
    if ($text -notmatch '(?s)^---\n(.*?)\n---\n(.*)$') { throw "No frontmatter: $Path" }
    $front = $Matches[1]
    $body = $Matches[2].Trim()
    $meta = [ordered]@{}
    foreach ($line in $front -split "`n") {
        if ($line -match '^([a-zA-Z0-9_-]+):\s*(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim() }
    }
    return @{ Meta = $meta; Body = $body }
}

$agents = @{}
foreach ($file in Get-ChildItem (Join-Path $root 'agents') -Filter *.md) {
    $agent = Read-MarkdownWithFrontmatter $file.FullName
    $name = $agent.Meta['name']
    $role = $roles.roles.PSObject.Properties[$name]
    if (-not $role) { throw "Agent '$name' has no entry in roles.json" }
    $claude = $role.Value.claude
    if ($agent.Meta['model'] -ne $claude.model -or $agent.Meta['effort'] -ne $claude.effort) {
        throw "Drift: agents/$($file.Name) is $($agent.Meta['model'])/$($agent.Meta['effort']), roles.json says $($claude.model)/$($claude.effort)"
    }
    $agents[$name] = $agent
}
foreach ($p in $roles.roles.PSObject.Properties) {
    if (-not $agents.ContainsKey($p.Name)) { throw "roles.json role '$($p.Name)' has no agents/*.md" }
}

$skillNames = @($manifest.skills | Sort-Object -Unique)
$slashPattern = '(?<![a-zA-Z0-9_.\-/])/(' + (($skillNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'

function Get-Rules([string]$HostName) {
    $text = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'CLAUDE.md')) -replace "`r`n", "`n"
    foreach ($n in '5', '6') {
        $replacement = $roles.rules.$HostName.$n
        $pattern = "(?m)^$n\. .*$"
        if ($text -notmatch $pattern) { throw "CLAUDE.md has no rule $n to adapt" }
        $text = [regex]::Replace($text, $pattern, { param($m) $replacement }, 1)
    }
    return $text.TrimEnd() + "`n"
}

function Assert-InsideHome([string]$Home_, [string]$Target) {
    $full = [IO.Path]::GetFullPath($Target)
    if (-not $full.StartsWith($Home_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside ${Home_}: $full"
    }
    return $full
}

function Write-Generated([string]$Home_, [string]$Relative, [string]$Content) {
    $target = Assert-InsideHome $Home_ (Join-Path $Home_ $Relative)
    $existing = if (Test-Path -LiteralPath $target -PathType Leaf) { [IO.File]::ReadAllText($target) } else { $null }
    if ($existing -ceq $Content) { return }
    if ($PSCmdlet.ShouldProcess($target, 'Write generated file')) {
        if ($null -ne $existing) {
            $backup = Assert-InsideHome $Home_ (Join-Path $Home_ (Join-Path 'portable-backups' (Join-Path $stamp $Relative)))
            New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup -Force
        }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        [IO.File]::WriteAllText($target, $Content, $utf8)
    }
}

function Remove-StaleFiles([string]$Home_, [string]$RelativeDir, [string]$Extension, [string[]]$Keep) {
    $dir = Assert-InsideHome $Home_ (Join-Path $Home_ $RelativeDir)
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter "*$Extension" -File) {
        if ($Keep -contains $file.Name) { continue }
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove legacy file (backed up)')) {
            $backup = Assert-InsideHome $Home_ (Join-Path $Home_ (Join-Path 'portable-backups' (Join-Path $stamp (Join-Path $RelativeDir $file.Name))))
            New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $backup -Force
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}

function ConvertTo-QuotedYaml([string]$Value) {
    $clean = ($Value -replace '^"|"$', '') -replace '\\', '\\' -replace '"', '\"'
    return '"' + $clean + '"'
}

function Convert-SkillMarkdownText([string]$Text, $Adapter) {
    $out = ($Text -replace "`r`n", "`n")
    $out = $out.Replace('.claude/skills/execute-ig', [string]$Adapter.executeScriptsRelPath)
    if ($Adapter.rewriteSlashToDollar -eq $true) {
        $out = [regex]::Replace($out, $slashPattern, '$$$1')
    }
    return $out
}

function Format-DisplayName([string]$SkillName) {
    $words = ($SkillName -replace '-ig$', '' -split '-') | ForEach-Object {
        if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) }
    }
    return ($words -join ' ')
}

function Sync-HostSkills([string]$Home_, [string]$HostName) {
    $adapter = $roles.skillAdapters.$HostName
    $skillsRel = [string]$adapter.skillsRelDir
    $skillsRoot = Assert-InsideHome $Home_ (Join-Path $Home_ $skillsRel)
    $preserve = @($adapter.preserveDirs)

    if (Test-Path -LiteralPath $skillsRoot) {
        foreach ($dir in Get-ChildItem -LiteralPath $skillsRoot -Directory -Force) {
            if ($preserve -contains $dir.Name) { continue }
            if ($skillNames -contains $dir.Name) {
                # Remove legacy wrapper subfolders (agents/openai.yaml in Antigravity, source-claude, source-brixbroker)
                foreach ($sub in Get-ChildItem -LiteralPath $dir.FullName -Force) {
                    $srcEquivalent = Join-Path $root (Join-Path 'skills' (Join-Path $dir.Name $sub.Name))
                    $isCodexOpenAi = ($HostName -eq 'codex' -and $sub.Name -eq 'agents')
                    if (-not (Test-Path -LiteralPath $srcEquivalent) -and -not $isCodexOpenAi) {
                        if ($PSCmdlet.ShouldProcess($sub.FullName, 'Remove legacy skill item (backed up)')) {
                            $relSub = Join-Path $skillsRel (Join-Path $dir.Name $sub.Name)
                            $backup = Assert-InsideHome $Home_ (Join-Path $Home_ (Join-Path 'portable-backups' (Join-Path $stamp $relSub)))
                            New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
                            Copy-Item -LiteralPath $sub.FullName -Destination $backup -Recurse -Force
                            Remove-Item -LiteralPath $sub.FullName -Recurse -Force
                        }
                    }
                }
                continue
            }
            if ($PSCmdlet.ShouldProcess($dir.FullName, 'Remove obsolete skill directory (backed up)')) {
                $relDir = Join-Path $skillsRel $dir.Name
                $backup = Assert-InsideHome $Home_ (Join-Path $Home_ (Join-Path 'portable-backups' (Join-Path $stamp $relDir)))
                New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
                Copy-Item -LiteralPath $dir.FullName -Destination $backup -Recurse -Force
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force
            }
        }
    }

    foreach ($skill in $skillNames) {
        $srcSkillDir = Join-Path $root (Join-Path 'skills' $skill)
        if (-not (Test-Path -LiteralPath $srcSkillDir)) { throw "Missing skill in repo: $skill" }
        $parsed = Read-MarkdownWithFrontmatter (Join-Path $srcSkillDir 'SKILL.md')
        $desc = Convert-SkillMarkdownText $parsed.Meta['description'] $adapter
        $body = Convert-SkillMarkdownText $parsed.Body $adapter
        $preamble = [string]$adapter.preamble

        $skillMd = "---`nname: $skill`ndescription: $(ConvertTo-QuotedYaml $desc)`n---`n`n$preamble`n`n$body`n"
        Write-Generated $Home_ (Join-Path $skillsRel (Join-Path $skill 'SKILL.md')) $skillMd

        if ($HostName -eq 'codex') {
            $implicit = if ($parsed.Meta.Contains('disable-model-invocation') -and $parsed.Meta['disable-model-invocation'] -eq 'true') { 'false' } else { 'true' }
            $disp = Format-DisplayName $skill
            $short = "Workflow $skill projected from canonical harness"
            if ($short.Length -gt 60) { $short = $short.Substring(0, 60) }
            $openAiYaml = "interface:`n" +
                "  display_name: $(ConvertTo-QuotedYaml $disp)`n" +
                "  short_description: $(ConvertTo-QuotedYaml $short)`n" +
                "  default_prompt: $(ConvertTo-QuotedYaml "Use `$$skill to run this workflow in Codex.")`n" +
                "policy:`n" +
                "  allow_implicit_invocation: $implicit`n"
            Write-Generated $Home_ (Join-Path $skillsRel (Join-Path $skill 'agents/openai.yaml')) $openAiYaml
        }

        foreach ($child in Get-ChildItem -LiteralPath $srcSkillDir -Recurse -File) {
            if ($child.Name -eq 'SKILL.md') { continue }
            $relInsideSkill = $child.FullName.Substring($srcSkillDir.Length).TrimStart('\', '/')
            $targetRel = Join-Path $skillsRel (Join-Path $skill $relInsideSkill)
            if ($child.Extension -ieq '.md') {
                $childText = Convert-SkillMarkdownText (Get-Content -Raw -Encoding UTF8 $child.FullName) $adapter
                Write-Generated $Home_ $targetRel ($childText.TrimEnd() + "`n")
            } else {
                $rawText = (Get-Content -Raw -Encoding UTF8 $child.FullName) -replace "`r`n", "`n"
                Write-Generated $Home_ $targetRel $rawText
            }
        }
    }
}

if ($Hosts -contains 'codex') {
    $home_ = [IO.Path]::GetFullPath($CodexHome).TrimEnd('\', '/')
    Write-Generated $home_ 'AGENTS.md' (Get-Rules 'codex')
    $keep = @()
    foreach ($name in $agents.Keys | Sort-Object) {
        $cfg = $roles.roles.$name.codex
        $file = "$name.toml"
        $keep += $file
        $agent = $agents[$name]
        if ($agent.Body.Contains("'''")) { throw "Agent '$name' body contains '''" }
        $toml = "name = $(ConvertTo-QuotedYaml $name)`n" +
            "description = $(ConvertTo-QuotedYaml $agent.Meta['description'])`n" +
            "model = $(ConvertTo-QuotedYaml $cfg.model)`n" +
            "model_reasoning_effort = $(ConvertTo-QuotedYaml $cfg.effort)`n" +
            "developer_instructions = '''`n$($agent.Body)`n'''`n"
        Write-Generated $home_ "agents/$file" $toml
    }
    Remove-StaleFiles $home_ 'agents' '.toml' $keep
    Sync-HostSkills $home_ 'codex'
}

if ($Hosts -contains 'antigravity') {
    $home_ = [IO.Path]::GetFullPath($GeminiHome).TrimEnd('\', '/')
    Write-Generated $home_ 'GEMINI.md' (Get-Rules 'antigravity')
    $keep = @()
    foreach ($name in $agents.Keys | Sort-Object) {
        $cfg = $roles.roles.$name.antigravity
        $file = "$name.md"
        $keep += $file
        $agent = $agents[$name]
        $md = "---`nname: $name`ndescription: $($agent.Meta['description'])`nmodel: $($cfg.model)`n---`n`n" +
            "Reasoning effort: $($cfg.effort). Match depth of analysis to this level.`n`n$($agent.Body)`n"
        Write-Generated $home_ "config/agents/$file" $md
    }
    Remove-StaleFiles $home_ 'config/agents' '.md' $keep
    Sync-HostSkills $home_ 'antigravity'
}

if ($PurgeLegacyHomes) {
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $archiveRoot = Join-Path $userProfile (Join-Path '.claude\portable-backups' "legacy-v4-$stamp")
    foreach ($legacyName in @('.agentic-harness', '.agents')) {
        $legacyPath = Join-Path $userProfile $legacyName
        if (-not (Test-Path -LiteralPath $legacyPath)) { continue }
        if ($PSCmdlet.ShouldProcess($legacyPath, "Archive to $archiveRoot and remove legacy v4 directory")) {
            New-Item -ItemType Directory -Force $archiveRoot | Out-Null
            Move-Item -LiteralPath $legacyPath -Destination (Join-Path $archiveRoot $legacyName) -Force
        }
    }
    foreach ($codexLegacy in @('plans', 'memory-bank')) {
        $p = Join-Path $CodexHome $codexLegacy
        if (-not (Test-Path -LiteralPath $p)) { continue }
        if ($PSCmdlet.ShouldProcess($p, "Back up and remove legacy Codex directory")) {
            $backup = Join-Path $CodexHome (Join-Path 'portable-backups' (Join-Path $stamp $codexLegacy))
            New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
            Move-Item -LiteralPath $p -Destination $backup -Force
        }
    }
}
