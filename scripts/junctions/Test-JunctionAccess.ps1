#Requires -Version 5.1
<#
.SYNOPSIS
  Verifies junction folders listed in junctions_manifest.txt (see .cursorrules_General 1d.9).

.DESCRIPTION
  Cursor Glob sometimes misses junction contents; this script uses Test-Path and Get-ChildItem.

.PARAMETER RepoRoot
  DailySessionLogger_v2 repo root (default: two levels up from this script).

.EXAMPLE
  cd ...\DailySessionLogger_v2
  .\scripts\junctions\Test-JunctionAccess.ps1
#>
param(
    [string] $RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$manifest = Join-Path $PSScriptRoot "junctions_manifest.txt"
if (-not (Test-Path -LiteralPath $manifest)) {
    Write-Error "Missing manifest file: $manifest"
    exit 2
}

$lines = Get-Content -LiteralPath $manifest -Encoding UTF8
$failed = 0
$checked = 0

foreach ($raw in $lines) {
    $line = $raw.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { continue }

    $rel = $line -replace "/", "\"
    $full = Join-Path $RepoRoot $rel

    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "[FAIL] Missing path: $rel -> $full" -ForegroundColor Red
        $failed++
        continue
    }

    $checked++
    try {
        # Listing probe: dead junction or permission error
        $items = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)
        if ($items.Count -gt 0) {
            $sample = "entries visible: $($items.Count)+"
        } else {
            $sample = "empty folder"
        }
        Write-Host "[OK]   $rel (readable; $sample)"
    }
    catch {
        Write-Host "[FAIL] $rel listing error: $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host "--- Checked: $checked, failures: $failed ---"
if ($failed -gt 0) { exit 1 }
if ($checked -eq 0) {
    Write-Host "WARNING: manifest has no active paths (comments only?)." -ForegroundColor Yellow
}
exit 0
