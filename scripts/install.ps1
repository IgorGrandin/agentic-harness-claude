[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude')
)

# Installs only what manifest.json lists: CLAUDE.md, the agents, and the skills.
# Everything else under ClaudeHome (settings, projects, sessions, plugins,
# brixbroker metrics) is never read or written. Replaced items are backed up
# first under portable-backups/<timestamp>/.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'manifest.json') | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw "Unsupported manifest schema: $($manifest.schemaVersion)" }

$home_ = [IO.Path]::GetFullPath($ClaudeHome).TrimEnd('\', '/')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $home_ (Join-Path 'portable-backups' $stamp)

function Assert-Inside([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($home_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside ${home_}: $full"
    }
    return $full
}

function Get-Source([string]$Relative) {
    $path = Join-Path $root $Relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing source: $Relative" }
    return $path
}

function Backup-Item([string]$Target, [string]$Relative) {
    if (-not (Test-Path -LiteralPath $Target)) { return }
    $destination = Assert-Inside (Join-Path $backupRoot $Relative)
    if ($PSCmdlet.ShouldProcess($Target, "Back up to $destination")) {
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath $Target -Destination $destination -Recurse -Force
    }
}

function Install-File([string]$Relative) {
    $source = Get-Source $Relative
    $target = Assert-Inside (Join-Path $home_ $Relative)
    Backup-Item $target $Relative
    if ($PSCmdlet.ShouldProcess($target, 'Install file')) {
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Install-Directory([string]$Relative) {
    $source = Get-Source $Relative
    $target = Assert-Inside (Join-Path $home_ $Relative)
    Backup-Item $target $Relative
    if ($PSCmdlet.ShouldProcess($target, 'Replace directory')) {
        # Replace instead of merge, so files left by a previous harness
        # (for example agents/openai.yaml from v4) do not survive.
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
}

Install-File $manifest.instructions
foreach ($agent in $manifest.agents) { Install-File "agents\$agent.md" }
foreach ($skill in $manifest.skills) { Install-Directory "skills\$skill" }

$verb = if ($WhatIfPreference) { 'would install (WhatIf)' } else { 'installed' }
$summary = "agentic-harness-claude $verb into ${home_}: $(@($manifest.agents).Count) agents, $(@($manifest.skills).Count) skills"
if (Test-Path -LiteralPath $backupRoot) { $summary += "; backup at $backupRoot" }
Write-Host $summary
