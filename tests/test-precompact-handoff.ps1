[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hook = Join-Path $root 'hooks/precompact-handoff.ps1'
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

# Runs the hook in a child PowerShell with the given stdin text and a temp ClaudeHome.
function Invoke-Hook([string]$Stdin, [string]$ClaudeHome) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hook`" -ClaudeHome `"$ClaudeHome`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Stdin)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Exit = $p.ExitCode; Out = $out.Trim(); Err = $err.Trim() }
}
function Payload([string]$Trigger, [string]$Id) { (@{ session_id = $Id; trigger = $Trigger; hook_event_name = 'PreCompact' } | ConvertTo-Json -Compress) }
function Files([string]$Dir) { @(Get-ChildItem -LiteralPath $Dir -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($Dir.Length).TrimStart('\', '/') }) }

$temp = Join-Path ([IO.Path]::GetTempPath()) "harness-precompact-$([Guid]::NewGuid().ToString('N'))"
try {
    $id = 'abcdef12-3456-7890-abcd-ef1234567890'

    # auto, first time: blocks, writes the request and the sentinel.
    $h1 = Join-Path $temp 'first/.claude'
    $r = Invoke-Hook (Payload 'auto' $id) $h1
    Require ($r.Exit -eq 0) "auto/first: exit $($r.Exit)"
    $o = $r.Out | ConvertFrom-Json
    Require ($o.decision -eq 'block') 'auto/first: stdout is not decision=block'
    Require (-not [string]::IsNullOrWhiteSpace($o.reason)) 'auto/first: empty reason'
    Require (Test-Path -LiteralPath (Join-Path $h1 "handoffs/.request-$id")) 'auto/first: .request file missing'
    Require (Test-Path -LiteralPath (Join-Path $h1 "handoffs/.precompact-blocked-$id")) 'auto/first: sentinel missing'

    # auto, sentinel present: does not block, removes the sentinel, logs. Request is not rewritten.
    Remove-Item -LiteralPath (Join-Path $h1 "handoffs/.request-$id") -Force
    $r = Invoke-Hook (Payload 'auto' $id) $h1
    Require ($r.Exit -eq 0) "auto/sentinel: exit $($r.Exit)"
    Require ($r.Out -eq '') "auto/sentinel: blocked anyway: $($r.Out)"
    Require (-not (Test-Path -LiteralPath (Join-Path $h1 "handoffs/.precompact-blocked-$id"))) 'auto/sentinel: sentinel not removed'
    Require (-not (Test-Path -LiteralPath (Join-Path $h1 "handoffs/.request-$id"))) 'auto/sentinel: request rewritten'
    $log = Get-Content -Raw -LiteralPath (Join-Path $h1 'handoffs/handoff.log')
    Require ($log -match 'abcdef12 precompact') 'auto/sentinel: handoff.log lacks the line'

    # Third attempt after the fail-open blocks again (once in a row, not once per session).
    $r = Invoke-Hook (Payload 'auto' $id) $h1
    Require (($r.Out | ConvertFrom-Json).decision -eq 'block') 'auto/third: should block again'

    # Cases that must write nothing, print nothing, exit 0.
    $cases = [ordered]@{
        'manual'        = Payload 'manual' $id
        'invalid json'  = '{not json'
        'empty stdin'   = ''
        'path id'       = Payload 'auto' '..\x'
        'path id long'  = Payload 'auto' '..\..\evil-escape-xx'
        'slash id'      = Payload 'auto' 'abcdefgh/../../x'
        'short id'      = Payload 'auto' 'abc'
        'missing id'    = '{"trigger":"auto"}'
        'null json'     = 'null'
    }
    foreach ($name in $cases.Keys) {
        $h = Join-Path $temp "none-$([Math]::Abs($name.GetHashCode()))/.claude"
        $parent = Split-Path $h
        $r = Invoke-Hook $cases[$name] $h
        Require ($r.Exit -eq 0) "${name}: exit $($r.Exit)"
        Require ($r.Out -eq '') "${name}: printed '$($r.Out)'"
        Require (-not (Test-Path -LiteralPath $h)) "${name}: created files under ClaudeHome"
        Require (@(Files $parent).Count -eq 0) "${name}: created files outside handoffs/"
    }

    # A hostile id must not create anything outside <home>/handoffs either.
    $h2 = Join-Path $temp 'hostile/.claude'
    New-Item -ItemType Directory -Force $h2 | Out-Null
    $null = Invoke-Hook (Payload 'auto' '..\..\evil-escape-xx') $h2
    Require (@(Files (Join-Path $temp 'hostile')).Count -eq 0) 'hostile id wrote files'

    # An unwritable ClaudeHome (a file where the directory should be) still exits 0 silently.
    $blocker = Join-Path $temp 'blocker'
    New-Item -ItemType Directory -Force $temp | Out-Null
    Set-Content -LiteralPath $blocker -Value 'x'
    $r = Invoke-Hook (Payload 'auto' $id) (Join-Path $blocker '.claude')
    Require ($r.Exit -eq 0 -and $r.Out -eq '') 'write failure: not fail-open'

    Write-Host 'precompact-handoff tests passed'
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
