[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidateSet('init', 'end')][string]$Action,
    [string]$WorkDir = (Get-Location).Path,
    [string]$WorkItem,
    [string]$MemoryDir
)

# Keeps the Claude Code auto-memory of one project folder scoped to ONE work item.
#   init: archives the notes of OTHER work items, restores the notes of this one
#         (from memory/arquivo), and creates a stub note when the WI has none.
#   end : archives every note of this WI. Nothing is ever deleted.
# A note belongs to a WI when its frontmatter has "wis: 3701, 3938" or, for files named
# wi-*, when the file name carries the number. Notes with no WI (environment facts)
# are never touched. The WI number comes from the branch (ADR-0039: ...3701-slug) or -WorkItem.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

function Get-ProjectKey([string]$Path) {
    return [regex]::Replace([IO.Path]::GetFullPath($Path).TrimEnd('\', '/'), '[^A-Za-z0-9]', '-')
}

$branch = ''
if (-not $WorkItem) {
    $branch = [string](& git -C $WorkDir branch --show-current 2>$null)
    if ($branch -match '(?:^|/)(\d{3,6})(?:[-_/]|$)') { $WorkItem = $Matches[1] }
}
if (-not $WorkItem) { throw "Nao achei o numero do WI na branch '$branch'. Passe -WorkItem <numero>." }

if (-not $MemoryDir) {
    $top = [string](& git -C $WorkDir rev-parse --show-toplevel 2>$null)
    if (-not $top) { $top = $WorkDir }
    $MemoryDir = Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\projects') (Join-Path (Get-ProjectKey $top) 'memory')
}
$MemoryDir = [IO.Path]::GetFullPath($MemoryDir)
$archiveDir = Join-Path $MemoryDir 'arquivo'
$indexPath = Join-Path $MemoryDir 'MEMORY.md'
if (-not (Test-Path -LiteralPath $MemoryDir)) {
    if ($Action -eq 'end') { Write-Output "Sem pasta de memoria em $MemoryDir. Nada a arquivar."; return }
    if ($PSCmdlet.ShouldProcess($MemoryDir, 'Criar pasta de memoria')) { New-Item -ItemType Directory -Force $MemoryDir | Out-Null }
}

function Read-Note([IO.FileInfo]$File) {
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $File.FullName
    $wis = @()
    $m = [regex]::Match($text, '(?m)^wis:\s*(.+?)\s*$')
    if ($m.Success) { $wis = @([regex]::Matches($m.Groups[1].Value, '\d{3,6}') | ForEach-Object { $_.Value }) }
    elseif ($File.Name -like 'wi-*') { $wis = @([regex]::Matches($File.BaseName, '\d{3,6}') | ForEach-Object { $_.Value }) }
    $name = [regex]::Match($text, '(?m)^name:\s*"?(.+?)"?\s*$')
    $desc = [regex]::Match($text, '(?m)^description:\s*"?(.+?)"?\s*$')
    return [pscustomobject]@{
        File = $File
        Wis = $wis
        Title = $(if ($name.Success) { $name.Groups[1].Value } else { $File.BaseName })
        Description = $(if ($desc.Success) { $desc.Groups[1].Value } else { '' })
    }
}

function Get-Notes([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $Dir -File -Filter '*.md' | Where-Object { $_.Name -ne 'MEMORY.md' } | ForEach-Object { Read-Note $_ })
}

$index = @()
if (Test-Path -LiteralPath $indexPath) { $index = @(Get-Content -Encoding UTF8 -LiteralPath $indexPath) }
$indexChanged = $false
$report = [Collections.Generic.List[string]]::new()

function Remove-IndexLine([string]$FileName) {
    $pattern = [regex]::Escape("]($FileName)")
    $kept = @($script:index | Where-Object { $_ -notmatch $pattern })
    if ($kept.Count -ne $script:index.Count) { $script:index = $kept; $script:indexChanged = $true }
}

function Add-IndexLine($Note) {
    $pattern = [regex]::Escape("]($($Note.File.Name))")
    if (@($script:index | Where-Object { $_ -match $pattern }).Count -gt 0) { return }
    $tail = $(if ($Note.Description) { " - $($Note.Description)" } else { '' })
    $script:index = @($script:index) + "- [$($Note.Title)]($($Note.File.Name))$tail"
    $script:indexChanged = $true
}

function Move-ToArchive($Note) {
    $target = Join-Path $archiveDir $Note.File.Name
    if (Test-Path -LiteralPath $target) { $target = Join-Path $archiveDir ("{0}-{1}{2}" -f $Note.File.BaseName, (Get-Date -Format 'yyyyMMdd-HHmmss'), $Note.File.Extension) }
    if ($PSCmdlet.ShouldProcess($Note.File.FullName, "Mover para $target")) {
        New-Item -ItemType Directory -Force $archiveDir | Out-Null
        Move-Item -LiteralPath $Note.File.FullName -Destination $target
    }
    Remove-IndexLine $Note.File.Name
    $others = @($Note.Wis | Where-Object { $_ -ne $WorkItem })
    $extra = $(if ($Action -eq 'end' -and $others.Count -gt 0) { " (cita tambem WI $($others -join ', '))" } else { '' })
    $report.Add("arquivada: $($Note.File.Name)$extra")
}

$active = @(Get-Notes $MemoryDir)

if ($Action -eq 'end') {
    foreach ($note in @($active | Where-Object { $WorkItem -in $_.Wis })) { Move-ToArchive $note }
    if ($report.Count -eq 0) { $report.Add("nenhuma nota ativa do WI $WorkItem") }
}
else {
    foreach ($note in @($active | Where-Object { $_.Wis.Count -gt 0 -and $WorkItem -notin $_.Wis })) { Move-ToArchive $note }
    foreach ($note in @(Get-Notes $archiveDir | Where-Object { $WorkItem -in $_.Wis })) {
        $target = Join-Path $MemoryDir $note.File.Name
        if (Test-Path -LiteralPath $target) { $report.Add("nao restaurada (ja existe ativa): $($note.File.Name)"); continue }
        if ($PSCmdlet.ShouldProcess($note.File.FullName, "Restaurar para $target")) {
            Move-Item -LiteralPath $note.File.FullName -Destination $target
        }
        Add-IndexLine (Read-Note (New-Object IO.FileInfo $target))
        $report.Add("restaurada: $($note.File.Name)")
    }
    $now = @(Get-Notes $MemoryDir | Where-Object { $WorkItem -in $_.Wis })
    if ($now.Count -eq 0) {
        $stub = Join-Path $MemoryDir "wi-$WorkItem-estado.md"
        $date = Get-Date -Format 'yyyy-MM-dd'
        $where = $(if ($branch) { " na branch $branch" } else { '' })
        $body = "---`nname: wi-$WorkItem-estado`ndescription: Estado da WI $WorkItem (iniciado em $date)`nwis: $WorkItem`nmetadata:`n  type: project`n---`n`nMemoria da WI $WorkItem iniciada por /init-memory em $date$where. Registre aqui so o que e desta WI.`n"
        if ($PSCmdlet.ShouldProcess($stub, 'Criar nota inicial')) {
            [IO.File]::WriteAllText($stub, $body, $utf8)
            Add-IndexLine (Read-Note (New-Object IO.FileInfo $stub))
        }
        $report.Add("criada: wi-$WorkItem-estado.md")
    }
}

if ($indexChanged -and $PSCmdlet.ShouldProcess($indexPath, 'Reescrever indice')) {
    [IO.File]::WriteAllLines($indexPath, [string[]]@($index), $utf8)
}

Write-Output "WI $WorkItem | memoria: $MemoryDir"
foreach ($line in $report) { Write-Output "  $line" }
Write-Output ('  ativas agora: ' + ((@(Get-Notes $MemoryDir | ForEach-Object { $_.File.Name })) -join ', '))
