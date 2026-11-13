[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'),
    # Claude Code CLI used to register the mods (claude plugin install). Default: `claude` on PATH,
    # used only when ClaudeHome is the real ~/.claude. Passing it explicitly opts in for any ClaudeHome.
    [string]$PluginCli,
    [switch]$SkipPluginInstall
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

$AutoCompactWindow = 300000
$PreCompactScript = 'precompact-handoff.ps1'

# Sets the top-level auto-compact window and drops the per-model override of the
# Sonnet window (empty model object, then empty modelSettings, are removed too).
function Set-CompactWindow($Settings) {
    Set-Property $Settings 'autoCompactWindow' $AutoCompactWindow
    $models = $Settings.PSObject.Properties['modelSettings']
    if (-not $models -or $null -eq $models.Value) { return }
    $sonnet = $models.Value.PSObject.Properties['claude-sonnet-5-5']
    if ($sonnet -and $null -ne $sonnet.Value) {
        if ($sonnet.Value.PSObject.Properties['autoCompactWindow']) { $sonnet.Value.PSObject.Properties.Remove('autoCompactWindow') }
        if (@($sonnet.Value.PSObject.Properties).Count -eq 0) { $models.Value.PSObject.Properties.Remove('claude-sonnet-5-5') }
    }
    if (@($models.Value.PSObject.Properties).Count -eq 0) { $Settings.PSObject.Properties.Remove('modelSettings') }
}

# The PreCompact block of earlier versions did not hold (the second auto-compact ran seconds
# later), so the handoff now comes from the mod at 190k. Drops the entry this harness added
# and keeps every other PreCompact entry.
function Remove-PreCompactHook($Settings) {
    if (-not $Settings.PSObject.Properties['hooks'] -or $null -eq $Settings.hooks) { return }
    $prop = $Settings.hooks.PSObject.Properties['PreCompact']
    if (-not $prop) { return }
    $kept = @(@($prop.Value) | Where-Object {
        $entry = $_
        -not ($entry -and $entry.PSObject.Properties['hooks'] -and @($entry.hooks | Where-Object { $_ -and $_.PSObject.Properties['command'] -and ([string]$_.command).Contains($PreCompactScript) }).Count)
    })
    if ($kept.Count) { Set-Property $Settings.hooks 'PreCompact' $kept } else { $Settings.hooks.PSObject.Properties.Remove('PreCompact') }
    if (@($Settings.hooks.PSObject.Properties).Count -eq 0) { $Settings.PSObject.Properties.Remove('hooks') }
}

# Registers the marketplace folder in settings.json and enables each mod in it.
# Also applies the compaction setting (window) and drops the old PreCompact hook entry in the same write,
# so one backup of the previous settings.json covers everything.
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
        Set-CompactWindow $settings
        Remove-PreCompactHook $settings
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        [IO.File]::WriteAllText($target, (($settings | ConvertTo-Json -Depth 32) + "`n"), (New-Object Text.UTF8Encoding($false)))
    }
}

# Writing enabledPlugins is not enough on a clean machine: Claude Code only lists a mod as installed
# (and starts its MCP servers and hooks) after `claude plugin install`. Installs the mods that are
# missing from plugins/installed_plugins.json. A failure is a warning: the files and settings are
# already in place and the command can be rerun by hand.
function Register-Mods([string]$Marketplace, [string]$MarketplacePath, [string[]]$Plugins) {
    if ($SkipPluginInstall -or $WhatIfPreference) { return }
    $defaultHome = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude')).TrimEnd('\', '/')
    $explicit = [bool]$PluginCli
    if (-not $explicit -and $home_ -ne $defaultHome) { return }
    $cli = if ($explicit) { $PluginCli } else { $c = Get-Command claude -ErrorAction SilentlyContinue; if ($c) { $c.Source } }
    if (-not $cli) { Write-Warning "claude CLI not found: run 'claude plugin install <mod>@$Marketplace' for each mod, or reinstall with it on PATH."; return }
    $listFile = Join-Path $home_ 'plugins\installed_plugins.json'
    $installed = if (Test-Path -LiteralPath $listFile) { Get-Content -Raw -Encoding UTF8 -LiteralPath $listFile } else { '' }
    $missing = @($Plugins | Where-Object { $installed -notmatch ('"' + [regex]::Escape("$_@$Marketplace") + '"') })
    # The CLI writes to stderr on failure; under $ErrorActionPreference = 'Stop' that would abort the install.
    function Invoke-Cli([string[]]$CliArgs) {
        $ErrorActionPreference = 'Continue'
        & $cli @CliArgs *> $null
        return $LASTEXITCODE
    }
    $failed = @()
    $marketAdded = $false
    foreach ($plugin in $missing) {
        $name = "$plugin@$Marketplace"
        $code = Invoke-Cli @('plugin', 'install', $name)
        if ($code -ne 0 -and -not $marketAdded) {
            # The marketplace may not be known to the CLI yet (clean machine): register the folder, then retry.
            $marketAdded = $true
            Invoke-Cli @('plugin', 'marketplace', 'add', $MarketplacePath) | Out-Null
            $code = Invoke-Cli @('plugin', 'install', $name)
        }
        if ($code -ne 0) { $failed += $name }
    }
    if ($failed.Count) { Write-Warning ("Could not install: {0}. Run 'claude plugin install <name>' for each, then restart Claude Code." -f ($failed -join ', ')) }
    Write-Host ("mods registered with the CLI: {0} installed, {1} already there, {2} failed" -f ($missing.Count - $failed.Count), (@($Plugins).Count - $missing.Count), $failed.Count)
}

Install-File $manifest.instructions
foreach ($agent in $manifest.agents) { Install-File "agents\$agent.md" }
foreach ($skill in $manifest.skills) { Install-Directory "skills\$skill" }

$mods = $manifest.mods
$modsRelative = "plugins\marketplaces\$($mods.marketplace)"
Install-Directory $mods.source $modsRelative
Merge-ModsSettings $mods.marketplace (Assert-Inside (Join-Path $home_ $modsRelative)) @($mods.items)
Register-Mods $mods.marketplace (Assert-Inside (Join-Path $home_ $modsRelative)) @($mods.items)

$verb = if ($WhatIfPreference) { 'would install (WhatIf)' } else { 'installed' }
$summary = "agentic-harness-claude $verb into ${home_}: $(@($manifest.agents).Count) agents, $(@($manifest.skills).Count) skills, $(@($mods.items).Count) mods"
if (Test-Path -LiteralPath $backupRoot) { $summary += "; backup at $backupRoot" }
Write-Host $summary
