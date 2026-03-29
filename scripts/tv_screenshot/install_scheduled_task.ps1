#Requires -Version 5.1
<#
  Rejestruje zadanie harmonogramu Windows: uruchomienie scheduled_screenshots.py przy logowaniu (bez okna, pythonw).

  WAZNE: .\scripts\... dziala TYLKO gdy biezacy katalog to ROOT repo DailySessionLogger_v2.
  Nie uruchamiaj z C:\Windows\System32 — najpierw: cd "...\DailySessionLogger_v2"

  Instalacja (1) wejdz do rootu repo, (2):
    .\scripts\tv_screenshot\install_scheduled_task.ps1

  Bez ustawiania Execution Policy: uruchom install_scheduled_task.cmd (w tym samym folderze).
  Pelna sciezka do Windows PowerShell 5.1 (gdy "powershell" nie jest w PATH):
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File "...\install_scheduled_task.ps1"

  Odinstalowanie:
    .\scripts\tv_screenshot\install_scheduled_task.ps1 -Remove

  Wymaga: .venv z playwright, Chromium (playwright install chromium).
#>
param(
    [string]$RepoRoot = "",
    [string]$TaskName = "DailySessionLogger_TV_Screenshots",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $here "..\..")).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}

$pythonw = Join-Path $RepoRoot ".venv\Scripts\pythonw.exe"
$scriptPy = Join-Path $here "scheduled_screenshots.py"

if ($Remove) {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Usunieto zadanie: $TaskName"
    } else {
        Write-Host "Brak zadania: $TaskName"
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $pythonw)) {
    Write-Error "Brak '$pythonw'. Z rootu repo: python -m venv .venv ; .\.venv\Scripts\pip install -r scripts\tv_screenshot\requirements.txt ; .\.venv\Scripts\playwright install chromium"
}

if (-not (Test-Path -LiteralPath $scriptPy)) {
    Write-Error "Brak pliku: $scriptPy"
}

$arg = "`"$scriptPy`""
$action = New-ScheduledTaskAction -Execute $pythonw -Argument $arg -WorkingDirectory $RepoRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopOnIdleEnd `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "OK: zarejestrowano zadanie '$TaskName'"
Write-Host "  Uruchomienie: przy logowaniu uzytkownika ($env:USERNAME)"
Write-Host "  Proces: $pythonw"
Write-Host "  Skrypt: $scriptPy"
Write-Host ""
Write-Host "Zatrzymanie tymczasowe: Stop-ScheduledTask -TaskName '$TaskName'  (lub Menedzer zadan)"
Write-Host "Usuniecie zadania:      .\scripts\tv_screenshot\install_scheduled_task.ps1 -Remove"
Write-Host "Pierwsze uruchomienie:  Start-ScheduledTask -TaskName '$TaskName'  (albo wyloguj sie i zaloguj)"
