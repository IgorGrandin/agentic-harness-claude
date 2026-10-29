[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude')
)

# Installs only what manifest.json lists: CLAUDE.md, the agents, the skills and the
# mods marketplace. Mods are copied to plugins/marketplaces/<name>, and settings.json
# gets only that marketplace and its enabledPlugins keys merged in. Everything else
# under ClaudeHome (projects, sessions, other plugins, brixbroker metrics, the rest of
# settings.json) is never read or written. Replaced items are backed up first under
# portable-backups/<timestamp>/.

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

function Install-Directory([string]$Relative, [string]$TargetRelative = $Relative) {
    $source = Get-Source $Relative
    $target = Assert-Inside (Join-Path $home_ $TargetRelative)
    Backup-Item $target $TargetRelative
    if ($PSCmdlet.ShouldProcess($target, 'Replace directory')) {
        # Replace instead of merge, so files left by a previous harness
        # (for example agents/openai.yaml from v4) do not survive.
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
}

function Set-Property($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# Registers the marketplace folder in settings.json and enables each mod in it.
# Every other key in settings.json is kept as it was.
function Merge-ModsSettings([string]$Marketplace, [string]$MarketplacePath, [string[]]$Plugins) {
    $target = Assert-Inside (Join-Path $home_ 'settings.json')
    Backup-Item $target 'settings.json'
    if ($PSCmdlet.ShouldProcess($target, "Register $Marketplace and enable $($Plugins.Count) mods")) {
        $settings = if (Test-Path -LiteralPath $target) { Get-Content -Raw -Encoding UTF8 -LiteralPath $target | ConvertFrom-Json } else { [pscustomobject]@{} }
        if (-not $settings.PSObject.Properties['extraKnownMarketplaces']) { Set-Property $settings 'extraKnownMarketplaces' ([pscustomobject]@{}) }
        if (-not $settings.PSObject.Properties['enabledPlugins']) { Set-Property $settings 'enabledPlugins' ([pscustomobject]@{}) }
        $marketSource = [pscustomobject]@{ source = [pscustomobject]@{ source = 'directory'; path = $MarketplacePath } }
        Set-Property $settings.extraKnownMarketplaces $Marketplace $marketSource
        foreach ($plugin in $Plugins) { Set-Property $settings.enabledPlugins "$plugin@$Marketplace" $true }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        [IO.File]::WriteAllText($target, (($settings | ConvertTo-Json -Depth 32) + "`n"), (New-Object Text.UTF8Encoding($false)))
    }
}

Install-File $manifest.instructions
foreach ($agent in $manifest.agents) { Install-File "agents\$agent.md" }
foreach ($skill in $manifest.skills) { Install-Directory "skills\$skill" }

$mods = $manifest.mods
$modsRelative = "plugins\marketplaces\$($mods.marketplace)"
Install-Directory $mods.source $modsRelative
Merge-ModsSettings $mods.marketplace (Assert-Inside (Join-Path $home_ $modsRelative)) @($mods.items)

$verb = if ($WhatIfPreference) { 'would install (WhatIf)' } else { 'installed' }
$summary = "agentic-harness-claude $verb into ${home_}: $(@($manifest.agents).Count) agents, $(@($manifest.skills).Count) skills, $(@($mods.items).Count) mods"
if (Test-Path -LiteralPath $backupRoot) { $summary += "; backup at $backupRoot" }
Write-Host $summary
