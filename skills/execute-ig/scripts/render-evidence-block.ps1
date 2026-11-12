[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [string]$GateManifest,
    [string]$RepoRoot,
    [string]$Out
)

# Renders the evidence block that the dev pastes in the PR description (execute-ig step 8).
# Everything comes from artifacts that already exist: the slice commit bodies (trailers
# Execute-Plan / Execute-Base / Execute-Slice) and, when given, the gate manifest. Nothing is
# invented: a section with no source says so.
# The block is tied to a commit: it names HEAD, and the script REFUSES (exit 1) when the tree is
# dirty or when the gate manifest was produced for another HEAD. A reviewer must re-check the
# SHA against the PR head before trusting any line of it.
# Exit 0 = block written, 1 = refused (stale or dirty), 2 = could not run.
# Saved as UTF-8 with BOM: Windows PowerShell 5.1 reads a BOM-less script as ANSI.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function T([string]$Escaped) { [regex]::Unescape($Escaped) }
function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}
function Invoke-Git([string[]]$GitArgs) {
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & git -C $RepoRoot -c core.quotepath=false @GitArgs 2>$null; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') failed with exit $code" }
    @($o | ForEach-Object { [string]$_ })
}
function Get-Section([string[]]$Lines, [string]$HeadingPattern) {
    # Lines after a heading line ("Heading:" or "Heading: text") up to the next blank line.
    $result = [Collections.Generic.List[string]]::new()
    $inside = $false
    foreach ($l in $Lines) {
        if (-not $inside) {
            if ($l -match "^(?:$HeadingPattern):\s*(.*)$") { $inside = $true; if ($Matches[1]) { $result.Add($Matches[1]) } }
        } else {
            if ([string]::IsNullOrWhiteSpace($l)) { break }
            $result.Add($l)
        }
    }
    @($result)
}

$prevEnc = $null
try {
    $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (& git rev-parse --show-toplevel) }
    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

    $planFull = if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $RepoRoot $PlanPath }
    if (-not (Test-Path -LiteralPath $planFull -PathType Leaf)) { throw "Plan not found: $PlanPath" }
    $planRel = ([IO.Path]::GetFullPath($planFull).Substring($RepoRoot.Length).TrimStart('\', '/')) -replace '\\', '/'

    $head = @(Invoke-Git @('rev-parse', 'HEAD'))[0]
    $dirty = @(Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all'))
    if ($dirty.Count) { Write-Output "REFUSED: the tree is not clean ($($dirty.Count) path(s)); the block must describe a commit."; exit 1 }

    $gate = $null
    if ($GateManifest) {
        if (-not (Test-Path -LiteralPath $GateManifest -PathType Leaf)) { throw "Gate manifest not found: $GateManifest" }
        $gate = Get-Content -Raw -Encoding UTF8 -LiteralPath $GateManifest | ConvertFrom-Json
        $gHead = [string](Get-Prop $gate 'HEAD'); if (-not $gHead) { $gHead = [string](Get-Prop $gate 'head') }
        if ($gHead -and $gHead -ne $head) { Write-Output "REFUSED: the gate manifest is for $($gHead.Substring(0,[Math]::Min(9,$gHead.Length))), HEAD is $($head.Substring(0,9)). Run the gate again against HEAD."; exit 1 }
    }

    $shas = @(Invoke-Git @('log', '--reverse', '--format=%H', '--fixed-strings', "--grep=Execute-Plan: $planRel"))
    $slices = [Collections.Generic.List[object]]::new()
    foreach ($sha in $shas) {
        $body = @((Invoke-Git @('log', '-1', '--format=%B', $sha)) | ForEach-Object { $_.TrimEnd() })
        if (-not ($body -contains "Execute-Plan: $planRel")) { continue }
        $id = ($body | Where-Object { $_ -match '^Execute-Slice:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
        $base = ($body | Where-Object { $_ -match '^Execute-Base:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
        $slices.Add([pscustomobject]@{
            Sha = $sha; Id = $id; Base = $base; Body = $body
            Trace = @(Get-Section $body 'Traceability|Rastreabilidade')
            Mutant = @(Get-Section $body 'Mutantes?')
            Reuse = @(Get-Section $body 'Reuso')
            Deviations = @(Get-Section $body 'Desvios')
            Claims = @(Get-Section $body 'Afirma\S+es')
            Decisions = @($body | Where-Object { $_ -match '^Decis\S+o D\d+:' })
        })
    }
    if ($slices.Count -eq 0) { throw "No slice commit with 'Execute-Plan: $planRel' was found." }

    $planText = [IO.File]::ReadAllText($planFull, [Text.Encoding]::UTF8)
    $boundaries = @()
    if ($planText -match '(?ms)^#{2,4}\s*Fronteiras[^\r\n]*\r?\n(.*?)(?=^#{1,4}\s|\z)') {
        $boundaries = @($Matches[1] -split '\r?\n' | Where-Object { $_ -match '^\s*[-*]\s+\S' } | ForEach-Object { $_.Trim() })
    }

    $sb = [Text.StringBuilder]::new()
    function Add([string]$Line) { [void]$sb.AppendLine($Line) }
    $shortHead = $head.Substring(0, 9)
    Add "<!-- execute-evidence head=$head plan=$planRel -->"
    Add "## $(T 'Evidência da entrega') (gerada pelo /execute-ig, n$(T 'ã')o editar $(T 'à') m$(T 'ã')o)"
    Add ''
    Add "- HEAD: ``$head`` (confira com o head da PR; se for outro, este bloco n$(T 'ã')o vale)"
    Add "- Plano: ``$planRel``; run base: ``$(@($slices)[0].Base)``; $($slices.Count) commit(s) de fatia"
    if ($gate) {
        $gStatus = [string](Get-Prop $gate 'status'); $gResult = [string](Get-Prop $gate 'result')
        $fp = [string](Get-Prop $gate 'gateTreeFingerprint')
        $fpText = if ($fp) { ", fingerprint ``$fp``" } else { '' }
        Add "- Gate local: status ``$gStatus``, result ``$gResult``$fpText (manifesto do mesmo HEAD)"
    } else {
        Add "- Gate local: manifesto n$(T 'ã')o informado; n$(T 'ã')o h$(T 'á') prova de gate neste bloco"
    }
    Add ''
    Add "### Fatias"
    foreach ($s in $slices) {
        $vis = ([regex]::Matches(($s.Trace -join "`n"), '\[visto\]')).Count
        $rac = ([regex]::Matches(($s.Trace -join "`n"), '\[raciocinado\]')).Count
        Add "- $($s.Id): ``$($s.Sha.Substring(0,9))`` $(T 'rastreabilidade') [visto] x$vis, [raciocinado] x$rac"
    }
    Add ''
    Add "### $(T 'Rastreabilidade e mutantes')"
    foreach ($s in $slices) {
        Add "**$($s.Id)**"
        if ($s.Trace.Count) { $s.Trace | ForEach-Object { Add $_ } } else { Add "- (sem se$(T 'çã')o de rastreabilidade no commit)" }
        if ($s.Mutant.Count) { Add "- Mutante: $($s.Mutant -join ' ')" } else { Add "- Mutante: nenhum registrado no commit" }
    }
    Add ''
    Add "### Fronteiras produtor$(T '→')consumidor, concorr$(T 'ê')ncia e entrada externa"
    if ($boundaries.Count) { $boundaries | ForEach-Object { Add $_ } } else { Add "- o plano n$(T 'ã')o declara fronteiras; o revisor deve deriv$(T 'á')-las do diff" }
    Add ''
    Add "### $(T 'Decisões do dev')"
    $allDecisions = @($slices | ForEach-Object { $_.Decisions })
    $diverging = @($allDecisions | Where-Object { $_ -match '(?i)diverg' })
    if ($allDecisions.Count) { $allDecisions | ForEach-Object { Add "- $_" } } else { Add "- nenhuma registrada nos commits" }
    Add ''
    Add "**$(T 'Decisões que divergem do texto da spec ou de um critério') (o owner ratifica ou rejeita nesta PR):** $(if ($diverging.Count) { '' } else { 'nenhuma' })"
    $diverging | ForEach-Object { Add "- $_" }
    Add ''
    Add "### Desvios do plano"
    $devs = @($slices | ForEach-Object { $s = $_; $s.Deviations | Where-Object { $_ -and $_ -notmatch '^(?i)nenhum' } | ForEach-Object { "$($s.Id): $_" } })
    if ($devs.Count) { $devs | ForEach-Object { Add "- $_" } } else { Add "- nenhum" }
    Add ''
    Add "### $(T 'Afirmações e provas')"
    foreach ($s in $slices) {
        $claims = @($s.Claims | Where-Object { $_ -and $_ -notmatch '^(?i)nenhuma' })
        if ($claims.Count) { Add "**$($s.Id)**"; $claims | ForEach-Object { Add $_ } }
    }

    $text = $sb.ToString()
    if ($Out) { [IO.File]::WriteAllText($Out, $text, [Text.UTF8Encoding]::new($false)); Write-Output "Evidence block written to $Out (HEAD $shortHead, $($slices.Count) slice commit(s))." }
    else { Write-Output $text }
    exit 0
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 2
} finally { if ($prevEnc) { [Console]::OutputEncoding = $prevEnc } }
