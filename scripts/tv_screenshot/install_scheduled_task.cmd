@echo off
REM Instalacja zadania harmonogramu (TV screenshots). Nie wymaga PATH do "powershell".
REM Uruchom z Eksploratora (dwuklik) albo:  scripts\tv_screenshot\install_scheduled_task.cmd
REM Odinstalowanie:  install_scheduled_task.cmd -Remove

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo Nie znaleziono: %PS%
  exit /b 1
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_scheduled_task.ps1" %*
