#requires -Version 5.1
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): denies hand edits to
# generated OpenAPI type files (item 3 of the owner's blockers list in
# CLAUDE.local.md). The generator runs through the shell, which this hook
# does not match, so `npm run gen:broker-api` keeps working.

$ErrorActionPreference = 'Stop'
try { $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { exit 0 }
$input_ = $payload.PSObject.Properties['tool_input']
if (-not $input_) { exit 0 }
$path = $null
foreach ($name in @('file_path', 'notebook_path')) {
    $p = $input_.Value.PSObject.Properties[$name]
    if ($p -and $p.Value) { $path = [string]$p.Value; break }
}
if (-not $path -or ($path -replace '\\', '/') -notmatch '/generated/[^/]+\.types\.ts$') { exit 0 }

$reason = "Generated file: $path. Do not edit it by hand. Start the API and run npm run gen:broker-api (or gen:admin-api) in platform/frontend, then replace hand-declared types with the generated Schemas."
@{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } } | ConvertTo-Json -Depth 4 -Compress
exit 0
