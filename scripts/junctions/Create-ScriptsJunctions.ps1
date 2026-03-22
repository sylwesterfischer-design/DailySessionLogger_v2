#Requires -Version 5.1
param(
    [switch]$Force,
    [switch]$WhatIf
)
# Pomoc: tworzy junctiony scripts_<LOGIN> -> ...\MQL5\Scripts z istniejacych logs_<LOGIN>.
# Uruchom (z korzenia repo): powershell -ExecutionPolicy Bypass -File .\scripts\junctions\Create-ScriptsJunctions.ps1 [-WhatIf] [-Force]

$ErrorActionPreference = 'Stop'

# Katalog projektu = dwa poziomy w górę od scripts\junctions\ (PSScriptRoot bywa pusty w niektorych kontekstach)
$ScriptFile = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ScriptFile)) { $ScriptFile = $PSCommandPath }
if ([string]::IsNullOrWhiteSpace($ScriptFile)) { $ScriptFile = Join-Path $PSScriptRoot "Create-ScriptsJunctions.ps1" }
$ScriptDir = Split-Path -Parent $ScriptFile
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw "Nie udalo sie ustalic ProjectRoot (PSScriptRoot='$PSScriptRoot'). Uruchom: powershell -File .\scripts\junctions\Create-ScriptsJunctions.ps1"
}
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "ProjectRoot not found: $ProjectRoot"
}

# Loginy z reconcile skryptow - edytuj liste gdy dodasz nowe konto.
$ReconcileLogins = @(
    10828174,
    11693814,
    11693817,
    11720331
)

# --- Parsowanie listy junctionow z "cmd dir /AL" (dziala na starszym PS bez .Target na katalogu) ---
function Get-DirectoryJunctions {
    param([string]$Root)
    $result = @{}
    $out = cmd /c "cd /d `"$Root`" && dir /AL" 2>$null
    foreach ($line in $out) {
        # Przyklad: "21.03.2026  14:00    <JUNCTION>     logs_11720331 [C:\...\MQL5\Logs]"
        if ($line -match '\<JUNCTION\>\s+(\S+)\s+\[(.+)\]\s*$') {
            $name = $Matches[1].Trim()
            $target = $Matches[2].Trim()
            $result[$name] = $target
        }
    }
    return $result
}

function Get-LogsTargetForLogin {
    param(
        [hashtable]$JunctionMap,
        [uint64]$Login
    )
    $candidates = @(
        "logs_${Login}_terminal",
        "logs_${Login}"
    )
    foreach ($c in $candidates) {
        if ($JunctionMap.ContainsKey($c)) {
            return @{ Name = $c; Target = $JunctionMap[$c] }
        }
    }
    return $null
}

function Convert-Mql5LogsPathToScriptsPath {
    param([string]$LogsPath)
    if ([string]::IsNullOrWhiteSpace($LogsPath)) { return $null }
    $t = $LogsPath.TrimEnd('\')
    # Rozszerzona sciezka Win32 (junction czesto zwraca \??\C:\...)
    if ($t.StartsWith('\\?\')) { $t = $t.Substring(4) }
    elseif ($t.StartsWith('\??\')) { $t = $t.Substring(4) }
    # Standard: ...\MQL5\Logs -> ...\MQL5\Scripts
    if ($t -match '(?i)\\MQL5\\Logs$') {
        return ($t -replace '(?i)\\MQL5\\Logs$', '\MQL5\Scripts')
    }
    # Czesto junction logs_<LOGIN> celuje w ...\Terminal\<HASH>\Logs (bez segmentu MQL5 w sciezce)
    if ($t -match '(?i)\\Terminal\\[A-F0-9]{32}\\(Logs|logs)$') {
        return ($t -replace '(?i)\\(Logs|logs)$', '\MQL5\Scripts')
    }
    return $null
}

function Remove-JunctionLink {
    param([string]$Path)
    # Usuwa tylko dowiazanie (junction), nie cel.
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    cmd /c "rmdir `"$Path`"" | Out-Null
}

# --- Glowna logika ---
$map = Get-DirectoryJunctions -Root $ProjectRoot
Write-Host "ProjectRoot: $ProjectRoot" -ForegroundColor Cyan
Write-Host ""

foreach ($login in $ReconcileLogins) {
    # Reset - unikamy starej $scriptsTarget / $info przy continue miedzy iteracjami.
    $info = $null
    $scriptsTarget = $null

    $scriptsName = "scripts_$login"
    $scriptsPath = Join-Path $ProjectRoot $scriptsName
    if ([string]::IsNullOrWhiteSpace($scriptsPath)) {
        throw "Wewnetrzny blad: scriptsPath puste (ProjectRoot=$ProjectRoot login=$login)."
    }

    $info = Get-LogsTargetForLogin -JunctionMap $map -Login $login
    if (-not $info) {
        Write-Warning "[$login] Brak junctiona logs_${login}_terminal ani logs_${login} - pomijam (dodaj junction do Logs lub wpisz recznie)."
        continue
    }

    # Jawny [string] - gdy Target nie jest stringiem, unikamy dziwnych konwersji.
    $logsPathStr = [string]$info.Target
    $scriptsTarget = Convert-Mql5LogsPathToScriptsPath -LogsPath $logsPathStr
    if ($null -eq $scriptsTarget -or [string]::IsNullOrWhiteSpace($scriptsTarget)) {
        Write-Warning "[$login] Cel $($info.Name) -> $($info.Target) nie konczy sie na \MQL5\Logs - nie da sie wyliczyc Scripts."
        continue
    }

    # Test-Path -LiteralPath rzuca przy $null - zawsze mamy juz niepusty $scriptsTarget.
    if (-not (Test-Path -LiteralPath $scriptsTarget)) {
        Write-Warning "[$login] Docelowy folder Scripts nie istnieje: $scriptsTarget (MT5 zainstalowany / profil?)"
        continue
    }

    if (Test-Path -LiteralPath $scriptsPath) {
        # Sprawdz czy to juz poprawny junction
        $existing = $map[$scriptsName]
        if ($existing -and ($existing -ieq $scriptsTarget)) {
            Write-Host "[$login] OK: $scriptsName juz wskazuje na $scriptsTarget" -ForegroundColor Green
            continue
        }
        if (-not $Force) {
            Write-Warning "[$login] Istnieje $scriptsName ale inny cel niz oczekiwany. Uruchom z -Force aby nadpisac link."
            continue
        }
        if (-not $WhatIf) {
            Remove-JunctionLink -Path $scriptsPath
        } else {
            Write-Host "[$login] WhatIf: usunieto by junction $scriptsPath" -ForegroundColor Yellow
        }
    }

    if ($WhatIf) {
        Write-Host "[$login] WhatIf: New-Item Junction -Path `"$scriptsPath`" -Target `"$scriptsTarget`"" -ForegroundColor Yellow
    } else {
        New-Item -ItemType Junction -Path $scriptsPath -Target $scriptsTarget | Out-Null
        Write-Host "[$login] Utworzono: $scriptsName -> $scriptsTarget" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Gotowe. Kompilacja skryptow nadal: MetaEditor (F7) w profilu danego konta." -ForegroundColor Cyan
