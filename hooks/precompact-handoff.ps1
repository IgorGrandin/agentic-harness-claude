# PreCompact hook (matcher "auto"): turns an automatic compaction into a Refresh
# request for the handoff mod. Blocks the compaction at most once in a row per
# session; the second attempt finds the sentinel, removes it and lets it compact
# (fail-open, so a mod that never answers cannot block the session forever).
# Any error: exit 0 with no output, so the hook never breaks a session.
param(
    [string]$ClaudeHome = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude')
)

$ErrorActionPreference = 'Stop'
try {
    $stdin = New-Object IO.StreamReader([Console]::OpenStandardInput(), (New-Object Text.UTF8Encoding($false)))
    $raw = $stdin.ReadToEnd()
    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) { exit 0 }

    $trigger = [string]$data.trigger
    $id = [string]$data.session_id
    if ($trigger -ne 'auto') { exit 0 }
    if ($id -notmatch '^[0-9A-Za-z-]{8,}\z') { exit 0 }

    $dir = Join-Path $ClaudeHome 'handoffs'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $sentinel = Join-Path $dir ".precompact-blocked-$id"
    $request = Join-Path $dir ".request-$id"
    $utf8 = New-Object Text.UTF8Encoding($false)
    $now = [DateTime]::UtcNow.ToString('o')
    $logFile = Join-Path $dir 'handoff.log'
    $short = $id.Substring(0, 8)

    # Housekeeping: sentinels of long-gone sessions (older than a day) are removed.
    Get-ChildItem -LiteralPath $dir -Force -Filter '.precompact-blocked-*' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-1) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

    # A sentinel older than 15 minutes is an orphan (the blocked compaction never came back):
    # it no longer counts as "in a row", so this attempt blocks and asks for a Refresh again.
    if ((Test-Path -LiteralPath $sentinel) -and ((Get-Item -LiteralPath $sentinel -Force).LastWriteTimeUtc -lt [DateTime]::UtcNow.AddMinutes(-15))) {
        Remove-Item -LiteralPath $sentinel -Force
    }

    if (Test-Path -LiteralPath $sentinel) {
        Remove-Item -LiteralPath $sentinel -Force
        [IO.File]::AppendAllText($logFile, "$now $short precompact: second auto-compact in a row, letting it run`n", $utf8)
        exit 0
    }

    [IO.File]::WriteAllText($request, $now, $utf8)
    [IO.File]::WriteAllText($sentinel, $now, $utf8)
    [IO.File]::AppendAllText($logFile, "$now $short precompact: auto-compact blocked, Refresh requested`n", $utf8)
    $reason = 'Auto-compact blocked once: the handoff mod was asked for a Refresh. Write the handoff and continue in a new session, or run /compact to compact now.'
    Write-Output (@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress)
    exit 0
} catch {
    exit 0
}
