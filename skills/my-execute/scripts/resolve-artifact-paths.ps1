[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+$')][string]$WorkItem,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$CommitSha,
    [string]$HostTempRoot,
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$LocalAppDataRoot,
    [string]$EnvironmentTempRoot = $env:TEMP,
    [string]$Timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Timestamp -notmatch '^\d{8}-\d{6}$') { throw 'Timestamp must use yyyyMMdd-HHmmss.' }
$candidates = [Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($HostTempRoot)) {
    $candidates.Add([IO.Path]::GetFullPath($HostTempRoot))
} else {
    if (-not [string]::IsNullOrWhiteSpace($UserProfileRoot)) { $candidates.Add((Join-Path $UserProfileRoot 'AppData/Local/Temp')) }
    if ([string]::IsNullOrWhiteSpace($LocalAppDataRoot)) { $LocalAppDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }
    if (-not [string]::IsNullOrWhiteSpace($LocalAppDataRoot)) { $candidates.Add((Join-Path $LocalAppDataRoot 'Temp')) }
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentTempRoot)) { $candidates.Add($EnvironmentTempRoot) }
}
$validRoots = @($candidates | ForEach-Object {
    $candidateRoot = Join-Path ([IO.Path]::GetFullPath($_)) 'claude-handoffs/Broker'
    if ((Test-Path -LiteralPath $candidateRoot -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $candidateRoot 'execute-gates') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $candidateRoot 'execute-reports') -PathType Container)) {
        [IO.Path]::GetFullPath($candidateRoot)
    }
} | Select-Object -Unique)
if ($validRoots.Count -eq 0) { throw 'No existing canonical execute artifact root was found. Do not create a parallel artifact tree; pass -HostTempRoot only when the owner has identified the existing root.' }
if ($validRoots.Count -gt 1) { throw "Multiple existing execute artifact roots found; pass the owner-identified -HostTempRoot explicitly: $($validRoots -join '; ')" }
$brokerRoot = $validRoots[0]
$gateRoot = Join-Path $brokerRoot 'execute-gates'
$reportRoot = Join-Path $brokerRoot 'execute-reports'

$sha = $CommitSha.ToLowerInvariant()
$runId = [Guid]::NewGuid().ToString('N').Substring(0,8)
$base = "$Timestamp-wi$WorkItem-$sha-$runId"
$gateOutDir = Join-Path $gateRoot $base
$reportPath = Join-Path $reportRoot "$base.md"
if ((Test-Path -LiteralPath $gateOutDir) -or (Test-Path -LiteralPath $reportPath)) {
    throw "Execution artifact path already exists for this timestamp and commit: $base"
}
$result = [pscustomobject]@{
    WorkItem = $WorkItem
    CommitSha = $sha
    BrokerRoot = $brokerRoot
    GateOutDir = $gateOutDir
    ReportPath = $reportPath
}
if ($AsJson) { $result | ConvertTo-Json -Depth 4 -Compress } else { $result }
