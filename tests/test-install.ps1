[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer=Join-Path $root 'scripts/install.ps1'
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'manifest.json') | ConvertFrom-Json
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
$temp=Join-Path ([IO.Path]::GetTempPath()) "harness-install-$([Guid]::NewGuid().ToString('N'))"
$home_=Join-Path $temp '.claude'
try {
    # A ClaudeHome that looks like the v4 install plus the user's own state.
    New-Item -ItemType Directory -Force (Join-Path $home_ 'projects/p1'),(Join-Path $home_ 'brixbroker'),(Join-Path $home_ 'skills/plan-task/agents'),(Join-Path $home_ 'skills/my-own-skill'),(Join-Path $home_ 'agents') | Out-Null
    Set-Content -LiteralPath (Join-Path $home_ 'settings.json') -Value '{"hooks":{"sentinel":true}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $home_ 'projects/p1/memory.md') -Value 'user memory' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $home_ 'brixbroker/rodadas.csv') -Value 'header' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $home_ 'skills/my-own-skill/SKILL.md') -Value 'not managed' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $home_ 'skills/plan-task/SKILL.md') -Value '# Plan Task (Codex interface)' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $home_ 'skills/plan-task/agents/openai.yaml') -Value 'stale' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $home_ 'CLAUDE.md') -Value 'old global instructions' -Encoding UTF8
    $unmanaged=@('projects/p1/memory.md','brixbroker/rodadas.csv','skills/my-own-skill/SKILL.md')
    $before=@{}; foreach($p in $unmanaged){$before[$p]=Hash (Join-Path $home_ $p)}
    $settingsBefore=Hash (Join-Path $home_ 'settings.json')

    # -WhatIf changes nothing.
    & $installer -ClaudeHome $home_ -WhatIf | Out-Null
    Require ((Get-Content -Raw (Join-Path $home_ 'CLAUDE.md')).Trim() -eq 'old global instructions') '-WhatIf replaced CLAUDE.md'
    Require (-not (Test-Path (Join-Path $home_ 'portable-backups'))) '-WhatIf created a backup'
    Require ((Hash (Join-Path $home_ 'settings.json')) -eq $settingsBefore) '-WhatIf changed settings.json'

    & $installer -ClaudeHome $home_ | Out-Null

    foreach($p in $unmanaged){ Require ((Hash (Join-Path $home_ $p)) -eq $before[$p]) "Unmanaged file changed: $p" }
    # settings.json keeps its own keys and gains only the mods marketplace and its plugins.
    $settings=Get-Content -Raw -Encoding UTF8 (Join-Path $home_ 'settings.json') | ConvertFrom-Json
    Require ($settings.hooks.sentinel -eq $true) 'settings.json lost its own keys'
    $market=$settings.extraKnownMarketplaces.($manifest.mods.marketplace)
    Require ($market.source.source -eq 'directory') 'Mods marketplace is not a directory source'
    Require ($market.source.path -eq (Join-Path $home_ 'plugins\marketplaces\benai-mods')) 'Mods marketplace points outside ClaudeHome'
    foreach($m in $manifest.mods.items){ Require ($settings.enabledPlugins."$m@$($manifest.mods.marketplace)" -eq $true) "Mod not enabled: $m" }
    $modsHome=Join-Path $home_ 'plugins\marketplaces\benai-mods'
    Require (Test-Path (Join-Path $modsHome '.claude-plugin\marketplace.json')) 'Mods marketplace not installed'
    foreach($m in $manifest.mods.items){ Require (Test-Path (Join-Path $modsHome "plugins\$m\.claude-plugin\plugin.json")) "Mod not installed: $m" }
    Require ((Hash (Join-Path $home_ 'CLAUDE.md')) -eq (Hash (Join-Path $root 'CLAUDE.md'))) 'CLAUDE.md not installed from the repository'
    foreach($a in $manifest.agents){ Require (Test-Path (Join-Path $home_ "agents/$a.md")) "Agent not installed: $a" }
    foreach($s in $manifest.skills){ Require (Test-Path (Join-Path $home_ "skills/$s/SKILL.md")) "Skill not installed: $s" }
    Require (-not (Test-Path (Join-Path $home_ 'skills/plan-task/agents/openai.yaml'))) 'Stale v4 file survived the skill replacement'
    Require ((Get-Content -Raw (Join-Path $home_ 'skills/plan-task/SKILL.md')) -notmatch 'Codex interface') 'Old plan-task content survived'

    $backups=@(Get-ChildItem (Join-Path $home_ 'portable-backups') -Directory)
    Require ($backups.Count -eq 1) 'Expected exactly one backup directory'
    $b=$backups[0].FullName
    Require ((Get-Content -Raw (Join-Path $b 'CLAUDE.md')).Trim() -eq 'old global instructions') 'Backup lacks the previous CLAUDE.md'
    Require (Test-Path (Join-Path $b 'skills/plan-task/agents/openai.yaml')) 'Backup lacks the previous skill directory'
    Require ((Get-Content -Raw (Join-Path $b 'settings.json')) -notmatch 'benai-mods') 'Backup holds settings changed by the install'
    Require ((Get-Content -Raw (Join-Path $b 'settings.json')) -match 'sentinel') 'Backup lacks the previous settings.json'
    Write-Host 'install tests passed'
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
