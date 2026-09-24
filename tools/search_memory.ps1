[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Query,

    [ValidateRange(0, 3)]
    [int]$Context = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$memoryRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "docs\memory"
if (-not (Test-Path -LiteralPath $memoryRoot)) {
    throw "Memory directory not found: $memoryRoot"
}

$rg = Get-Command rg -ErrorAction SilentlyContinue
if ($null -ne $rg) {
    $arguments = @("-n", "-i", "-F", "-C", $Context.ToString(), "--glob", "*.md")
    foreach ($term in $Query) {
        $arguments += @("-e", $term)
    }
    $arguments += $memoryRoot
    & $rg.Source @arguments
    if ($LASTEXITCODE -eq 1) {
        Write-Host "No project-memory match for: $($Query -join ', ')"
        exit 1
    }
    exit $LASTEXITCODE
}

$matches = Get-ChildItem -LiteralPath $memoryRoot -File -Filter "*.md" |
    Select-String -SimpleMatch -CaseSensitive:$false -Pattern $Query -Context $Context

if ($null -eq $matches) {
    Write-Host "No project-memory match for: $($Query -join ', ')"
    exit 1
}

$matches | ForEach-Object {
    "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
}
