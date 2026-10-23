[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resolver=Join-Path $root 'skills/execute-ig/scripts/resolve-artifact-paths.ps1'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) "execute-artifacts-$([Guid]::NewGuid().ToString('N'))"
$canonical=Join-Path $temp 'claude-handoffs/Broker'
$gates=Join-Path $canonical 'execute-gates'; $reports=Join-Path $canonical 'execute-reports'
try {
    New-Item -ItemType Directory -Path $gates,$reports -Force | Out-Null
    $args=@{WorkItem='3572';CommitSha=('a'*40);HostTempRoot=$temp;Timestamp='20261015-123456';AsJson=$true}
    $one=& $resolver @args | ConvertFrom-Json
    $two=& $resolver @args | ConvertFrom-Json
    Require ($one.BrokerRoot -eq $canonical) 'Artifact path did not honor the supplied host LocalAppData temp root'
    Require ($one.GateOutDir.StartsWith($gates,[StringComparison]::OrdinalIgnoreCase) -and $one.ReportPath.StartsWith($reports,[StringComparison]::OrdinalIgnoreCase)) 'Gate/report paths escaped their canonical existing directories'
    Require ($one.GateOutDir -ne $two.GateOutDir -and $one.ReportPath -ne $two.ReportPath) 'Repeated path resolution produced colliding artifact paths'
    Require (-not (Test-Path $one.GateOutDir) -and -not (Test-Path $one.ReportPath)) 'Path resolution created artifact outputs before execution'
    $profile=Join-Path $temp 'profile'; $profileTemp=Join-Path $profile 'AppData/Local/Temp'
    $profileBroker=Join-Path $profileTemp 'claude-handoffs/Broker'
    New-Item -ItemType Directory -Path (Join-Path $profileBroker 'execute-gates'),(Join-Path $profileBroker 'execute-reports') -Force | Out-Null
    $fallback=& $resolver -WorkItem 3572 -CommitSha ('c'*40) -UserProfileRoot $profile -LocalAppDataRoot (Join-Path $temp 'sandbox-local') -EnvironmentTempRoot (Join-Path $temp 'sandbox-temp') -Timestamp '20261015-123456' -AsJson | ConvertFrom-Json
    Require ($fallback.BrokerRoot -eq $profileBroker) 'Resolver did not prefer the existing profile Temp root over sandbox Temp candidates'
    $actualProfileRoot=Join-Path $env:USERPROFILE 'AppData/Local/Temp/claude-handoffs/Broker'
    if ((Test-Path (Join-Path $actualProfileRoot 'execute-gates') -PathType Container) -and (Test-Path (Join-Path $actualProfileRoot 'execute-reports') -PathType Container)) {
        $actual=& $resolver -WorkItem 3572 -CommitSha ('e'*40) -AsJson | ConvertFrom-Json
        Require ($actual.BrokerRoot -eq [IO.Path]::GetFullPath($actualProfileRoot)) 'Default host path resolution ignored the existing user-profile Temp root'
    }
    $secondTemp=Join-Path $temp 'second-local-appdata'; $secondBroker=Join-Path $secondTemp 'Temp/claude-handoffs/Broker'
    New-Item -ItemType Directory -Path (Join-Path $secondBroker 'execute-gates'),(Join-Path $secondBroker 'execute-reports') -Force | Out-Null
    $failed=$false
    try { & $resolver -WorkItem 3572 -CommitSha ('d'*40) -UserProfileRoot $profile -LocalAppDataRoot $secondTemp -EnvironmentTempRoot (Join-Path $temp 'sandbox-temp') -Timestamp '20261015-123456' | Out-Null } catch { $failed=$true }
    Require $failed 'Multiple existing canonical roots did not require an explicit root'
    $missing=Join-Path $temp 'missing-root'
    $failed=$false
    try { & $resolver -WorkItem 3572 -CommitSha ('b'*40) -HostTempRoot $missing -Timestamp '20261015-123456' | Out-Null } catch { $failed=$true }
    Require ($failed -and -not (Test-Path $missing)) 'Missing canonical root was created or accepted'
    Remove-Item -LiteralPath $reports -Recurse -Force
    $failed=$false
    try { & $resolver -WorkItem 3572 -CommitSha ('b'*40) -HostTempRoot $temp -Timestamp '20261015-123456' | Out-Null } catch { $failed=$true }
    Require ($failed -and -not (Test-Path $reports)) 'Missing reports directory was silently recreated'
    Write-Host 'Execute artifact path focused tests passed.'
} finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force} }
