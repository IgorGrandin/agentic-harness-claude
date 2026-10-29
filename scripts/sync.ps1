[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('codex', 'antigravity')]
    [string[]]$Hosts = @('codex', 'antigravity'),
    [string]$CodexHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'),
    [string]$GeminiHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gemini')
)

# Generates the Codex and Antigravity global config from this repo's single source:
#   CLAUDE.md (rules), agents/*.md (role bodies), core/roles/roles.json (model/effort per host).
# Claude Code stays installed by install.ps1; here its roles.json values are only checked
# against agents/*.md frontmatter and the script fails on drift.
# Writes: <CodexHome>/AGENTS.md, <CodexHome>/agents/*.toml,
#         <GeminiHome>/GEMINI.md, <GeminiHome>/config/agents/*.md.
# Replaced items are backed up first under <home>/portable-backups/<timestamp>/.
# Nothing else under those homes is read or written (auth, sessions, skills, config.toml).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$roles = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'core/roles/roles.json') | ConvertFrom-Json
if ($roles.schemaVersion -ne 1) { throw "Unsupported roles schema: $($roles.schemaVersion)" }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-Agent([string]$Path) {
    $text = (Get-Content -Raw -Encoding UTF8 $Path) -replace "`r`n", "`n"
    if ($text -notmatch '(?s)^---\n(.*?)\n---\n(.*)$') { throw "No frontmatter: $Path" }
    $front = $Matches[1]
    $body = $Matches[2].Trim()
    $meta = @{}
    foreach ($line in $front -split "`n") {
        if ($line -match '^(\w+):\s*(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim() }
    }
    return @{ Meta = $meta; Body = $body }
}

$agents = @{}
foreach ($file in Get-ChildItem (Join-Path $root 'agents') -Filter *.md) {
    $agent = Read-Agent $file.FullName
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

function Write-Generated([string]$Home_, [string]$Relative, [string]$Content) {
    $target = [IO.Path]::GetFullPath((Join-Path $Home_ $Relative))
    if (-not $target.StartsWith($Home_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside ${Home_}: $target"
    }
    $existing = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) } else { $null }
    if ($existing -ceq $Content) { return }
    if ($PSCmdlet.ShouldProcess($target, 'Write generated file')) {
        if ($null -ne $existing) {
            $backup = Join-Path $Home_ (Join-Path 'portable-backups' (Join-Path $stamp $Relative))
            New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup -Force
        }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        [IO.File]::WriteAllText($target, $Content, $utf8)
    }
}

function Remove-Stale([string]$Home_, [string]$RelativeDir, [string]$Extension, [string[]]$Keep) {
    $dir = Join-Path $Home_ $RelativeDir
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter "*$Extension" -File) {
        if ($Keep -contains $file.Name) { continue }
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove legacy agent (backed up)')) {
            $backup = Join-Path $Home_ (Join-Path 'portable-backups' (Join-Path $stamp (Join-Path $RelativeDir $file.Name)))
            New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $backup -Force
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}

function ConvertTo-TomlString([string]$Value) {
    return '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
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
        $toml = "name = $(ConvertTo-TomlString $name)`n" +
            "description = $(ConvertTo-TomlString $agent.Meta['description'])`n" +
            "model = $(ConvertTo-TomlString $cfg.model)`n" +
            "model_reasoning_effort = $(ConvertTo-TomlString $cfg.effort)`n" +
            "developer_instructions = '''`n$($agent.Body)`n'''`n"
        Write-Generated $home_ "agents/$file" $toml
    }
    Remove-Stale $home_ 'agents' '.toml' $keep
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
    Remove-Stale $home_ 'config/agents' '.md' $keep
}
