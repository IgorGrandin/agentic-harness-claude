[CmdletBinding()]
param(
    [string]$TokensPath = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\metrics\tokens-by-model.csv'),
    [string]$RoundsPath = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\brixbroker\execute-rodadas.csv'),
    [switch]$AsJson
)

# Custo por WI: USD, sessoes, prompt medio por turno (papel x modelo) e planos distintos.
# Somente leitura. Prompt medio e aproximado: cache_read / messages.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$noWi = '(sem WI)'

foreach ($p in @($TokensPath, $RoundsPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "CSV not found: $p" }
}
# Import-Csv trata o BOM UTF-8 como parte do primeiro cabecalho em PS 5.1 quando lido como ANSI; forcar UTF8.
$tokens = @(Import-Csv -LiteralPath $TokensPath -Delimiter ';' -Encoding UTF8)
$rounds = @(Import-Csv -LiteralPath $RoundsPath -Delimiter ';' -Encoding UTF8)

function ConvertTo-Num([object]$Value) {
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return [double]0 }
    return [double]::Parse($s, $inv)
}

$wis = @{}
function Get-Entry([string]$Wi) {
    if (-not $wis.ContainsKey($Wi)) {
        $wis[$Wi] = @{ cost = [double]0; sessions = @{}; plans = @{}; groups = @{} }
    }
    return $wis[$Wi]
}

foreach ($r in $tokens) {
    $wi = ([string]$r.work_item).Trim()
    if (-not $wi) { $wi = $noWi }
    $e = Get-Entry $wi
    $e.cost += ConvertTo-Num $r.cost_usd
    $e.sessions[[string]$r.session_id] = $true
    $key = "$($r.role)|$($r.model)"
    if (-not $e.groups.ContainsKey($key)) {
        $e.groups[$key] = @{ role = [string]$r.role; model = [string]$r.model; messages = [double]0; cache_read = [double]0 }
    }
    $e.groups[$key].messages += ConvertTo-Num $r.messages
    $e.groups[$key].cache_read += ConvertTo-Num $r.cache_read
}

foreach ($r in $rounds) {
    $plan = ([string]$r.plan).Trim()
    if (-not $plan) { continue }
    $leaf = ($plan -replace '\\', '/').Split('/')[-1] -replace '\.plan\.md$', ''
    $wi = $noWi
    if ($leaf -match '^wi_([0-9A-Za-z]+)_') { $wi = $Matches[1] }
    (Get-Entry $wi).plans[$leaf] = $true
}

$rows = foreach ($wi in $wis.Keys) {
    $e = $wis[$wi]
    $breakdown = @(foreach ($g in ($e.groups.Values | Sort-Object { $_.role }, { $_.model })) {
        $avg = if ($g.messages -gt 0) { [math]::Round($g.cache_read / $g.messages, 0) } else { 0 }
        [pscustomobject][ordered]@{ role = $g.role; model = $g.model; messages = [int]$g.messages; avg_prompt_per_turn = [long]$avg }
    })
    [pscustomobject][ordered]@{
        work_item = $wi
        cost_usd  = [math]::Round($e.cost, 4)
        sessions  = $e.sessions.Count
        plans     = $e.plans.Count
        by_role_model = $breakdown
    }
}
$rows = @($rows | Sort-Object @{ Expression = { $_.work_item -eq $noWi } }, @{ Expression = { $_.cost_usd }; Descending = $true })

if ($AsJson) {
    ConvertTo-Json -InputObject $rows -Depth 5
    return
}

Write-Output 'Custo por WI (prompt medio por turno = cache_read / messages, aproximado)'
Write-Output ('{0,-10} {1,12} {2,9} {3,7}' -f 'WI', 'cost_usd', 'sessions', 'plans')
foreach ($row in $rows) {
    Write-Output ('{0,-10} {1,12} {2,9} {3,7}' -f $row.work_item, $row.cost_usd.ToString('0.0000', $inv), $row.sessions, $row.plans)
    foreach ($g in $row.by_role_model) {
        Write-Output ('    {0,-5} {1,-22} avg_prompt/turn ~{2,9}  (messages {3})' -f $g.role, $g.model, $g.avg_prompt_per_turn, $g.messages)
    }
}
