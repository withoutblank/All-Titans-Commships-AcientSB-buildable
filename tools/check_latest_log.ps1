[CmdletBinding()]
param(
    [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$LogsRoot = (Join-Path $env:LOCALAPPDATA "sins2\logs")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$latest = Get-ChildItem -LiteralPath $LogsRoot -File -Filter "*.txt" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $latest) {
    throw "No Sins II log found in $LogsRoot"
}

Write-Host "Latest log: $($latest.FullName)"
Write-Host "Written: $($latest.LastWriteTime)"

$lines = Get-Content -LiteralPath $latest.FullName
$escapedRoot = [regex]::Escape($ModRoot)
$blocks = [System.Collections.Generic.List[string]]::new()

for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match "Found errors for $escapedRoot") {
        $block = [System.Collections.Generic.List[string]]::new()
        $block.Add($lines[$index])
        for ($cursor = $index + 1; $cursor -lt $lines.Count; $cursor++) {
            if ($lines[$cursor] -match '^\[' -and $lines[$cursor] -notmatch '^\s*$') {
                break
            }
            if (-not [string]::IsNullOrWhiteSpace($lines[$cursor])) {
                $block.Add($lines[$cursor])
            }
        }
        $blocks.Add(($block -join [Environment]::NewLine))
    }
}

if ($blocks.Count -gt 0) {
    Write-Host ""
    Write-Host "MOD LOG CHECK FAILED ($($blocks.Count) entity error blocks)" -ForegroundColor Red
    foreach ($block in $blocks) {
        Write-Host ""
        Write-Host $block -ForegroundColor Red
    }
    exit 1
}

Write-Host "MOD LOG CHECK PASSED: no entity error block for this mod." -ForegroundColor Green
Write-Host "Note: mod.io 'Raw MS filesystem error 3' is service noise unless it names this mod's entity file."
exit 0
