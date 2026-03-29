@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "PYTHONUNBUFFERED=1"
set "IS_INTERACTIVE=0"
REM run_insert_pytest_last.log: nadpisywany na poczatku (ostatni run); linie z BAT: YYYY-MM-DD HH-mm-ss — docs/Loggers.md
set "LOGFILE=%~dp0run_insert_pytest_last.log"
call :ts
> "%LOGFILE%" echo !_TS! [START] run_insert_pytest.bat
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] CWD=%CD%

REM ============================================================
REM Wrapper uruchamiania insert_from_mt5_html.py w trybie pyTEST
REM Uzycie:
REM   run_insert_pytest.bat <KONTO> <YYYY-MM-DD> [LAYOUT]
REM Domyslnie: positions-pl = Raport Historii z klienta MT5 (sekcja Pozycje) — docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md
REM Opcjonalnie 3. arg: deals-default = tabela Deals z auto-HTML (ExportDailyHistoryHtml)
REM Przyklad:
REM   run_insert_pytest.bat 10827887 2026-03-18
REM   run_insert_pytest.bat 10827887 2026-03-18 deals-default
REM ============================================================

REM --- Tryb interaktywny dla 2x klik (bez argumentow) ---
if "%~1"=="" (
  set "IS_INTERACTIVE=1"
  echo [INPUT] Brak argumentow. Tryb interaktywny.
  call :ts
  >> "%LOGFILE%" echo !_TS! [INFO] Enter interactive mode
  set /p KONTO=Podaj KONTO ^(np. 10827887^): 
  set /p ONLY_DATE=Podaj ONLY_DATE ^(YYYY-MM-DD^): 
  REM Layout nie pytamy: domyslnie positions-pl (Raport Historii z MT5 — stale kolumny, patrz MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md)
  set "LAYOUT=positions-pl"
  echo [INFO] Layout=positions-pl ^(raport z menu MT5^). Dla auto-HTML EA: run_insert_pytest.bat KONTO DATA deals-default
  call :ts
  >> "%LOGFILE%" echo !_TS! [INFO] Layout fixed: positions-pl
) else (
  if "%~2"=="" goto :usage
  set "KONTO=%~1"
  set "ONLY_DATE=%~2"
  set "LAYOUT=%~3"
  if "%LAYOUT%"=="" set "LAYOUT=positions-pl"
)

REM --- Walidacja formatu konta (same cyfry) ---
for /f "delims=0123456789" %%A in ("%KONTO%") do (
  echo [ERROR] Konto musi byc liczba: "%KONTO%"
  >> "%LOGFILE%" echo [ERROR] Konto format invalid: %KONTO%
  goto :fail2
)

REM --- Walidacja formatu daty YYYY-MM-DD ---
set "YMD_Y="
set "YMD_M="
set "YMD_D="
for /f "tokens=1-3 delims=-" %%A in ("%ONLY_DATE%") do (
  set "YMD_Y=%%A"
  set "YMD_M=%%B"
  set "YMD_D=%%C"
)
if not defined YMD_Y goto :bad_date
if not defined YMD_M goto :bad_date
if not defined YMD_D goto :bad_date
if not "%YMD_Y:~4,1%"=="" goto :bad_date
if not "%YMD_M:~2,1%"=="" goto :bad_date
if not "%YMD_D:~2,1%"=="" goto :bad_date
for /f "delims=0123456789" %%A in ("%YMD_Y%%YMD_M%%YMD_D%") do goto :bad_date
goto :date_ok

:bad_date
echo [ERROR] only-date musi miec format YYYY-MM-DD, np. 2026-03-18
call :ts
>> "%LOGFILE%" echo !_TS! [ERROR] Date format invalid: %ONLY_DATE%
goto :fail2

:date_ok

REM --- Wymuszenie uruchomienia z katalogu glownego repo ---
set "SCRIPT_REL=scripts\csv_insert_from_mt5_html\insert_from_mt5_html.py"
if not exist "%SCRIPT_REL%" (
  echo [ERROR] Nie znaleziono "%SCRIPT_REL%".
  echo [HINT] Uruchom ten .bat z katalogu:
  echo        DailySessionLogger_v2
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing script: %SCRIPT_REL%
  goto :fail3
)

REM --- Budowa standardowych sciezek po konwencji projektu ---
set "REPORTS_DIR=reports_%KONTO%"
set "HTML_PRIMARY=%REPORTS_DIR%\ReportHistory-%KONTO%.html"
set "DEALS_IN=%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionDeals%KONTO%.csv"
set "SUMMARY_IN=%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionSummary.csv"

REM --- Walidacja wejsc: folder reports_<konto> ---
if not exist "%REPORTS_DIR%\" (
  echo [ERROR] Brak folderu "%REPORTS_DIR%\".
  echo [HINT] Utworz junction/folder zgodnie z JUNCTIONS_INVENTORY i namingiem reports_^<KONTO^>.
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing reports dir: %REPORTS_DIR%
  goto :fail4
)

REM --- Walidacja wejsc: CSV produkcyjne ---
if not exist "%DEALS_IN%" (
  echo [ERROR] Brak pliku deals-in:
  echo         "%DEALS_IN%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing deals csv: %DEALS_IN%
  goto :fail5
)
if not exist "%SUMMARY_IN%" (
  echo [ERROR] Brak pliku summary-in:
  echo         "%SUMMARY_IN%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing summary csv: %SUMMARY_IN%
  goto :fail6
)

REM --- Wykrycie HTML: preferuj ReportHistory-<konto>.html, fallback do pierwszego pasujacego ---
set "HTML_PATH="
if exist "%HTML_PRIMARY%" (
  set "HTML_PATH=%HTML_PRIMARY%"
) else (
  for /f "delims=" %%F in ('dir /b /a:-d "%REPORTS_DIR%\ReportHistory*%KONTO%*.htm*" 2^>nul') do (
    if not defined HTML_PATH set "HTML_PATH=%REPORTS_DIR%\%%F"
  )
)

if not defined HTML_PATH (
  echo [ERROR] Nie znaleziono pliku HTML dla konta %KONTO% w "%REPORTS_DIR%\".
  echo [EXPECT] "%HTML_PRIMARY%" lub "ReportHistory*%KONTO%*.html"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing html in %REPORTS_DIR%
  goto :fail7
)

REM --- Uruchomienie Pythona w trybie pyTEST + raport jakosci ---
echo [INFO] Konto      : %KONTO%
echo [INFO] Only date  : %ONLY_DATE%
echo [INFO] Layout     : %LAYOUT%
echo [INFO] HTML       : %HTML_PATH%
echo [INFO] Deals in   : %DEALS_IN%
echo [INFO] Summary in : %SUMMARY_IN%
echo [INFO] Log file   : %LOGFILE%
echo.
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] Konto=%KONTO% Date=%ONLY_DATE% Layout=%LAYOUT%
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] HTML=%HTML_PATH%
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] --- Python stdout (pyTEST) — linie z Pythona bez znacznika czasu z BAT ---

py "%SCRIPT_REL%" ^
  --layout "%LAYOUT%" ^
  --html "%HTML_PATH%" ^
  --konto "%KONTO%" ^
  --summary-in "%SUMMARY_IN%" ^
  --only-date "%ONLY_DATE%" ^
  --deals-in "%DEALS_IN%" ^
  --qa-report ^
  --test-outputs >> "%LOGFILE%"

set "RC=!ERRORLEVEL!"
if not "!RC!"=="0" (
  echo.
  echo [ERROR] insert_from_mt5_html zakonczyl sie kodem !RC!.
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Python exited with !RC!
  goto :fail_python
)

echo.
echo [OK] Zakonczono powodzeniem.
echo [OUT] "%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionDeals%KONTO%_pyTEST.csv"
echo [OUT] "%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionSummary_pyTEST.csv"
call :ts
>> "%LOGFILE%" echo !_TS! [OK] Finished with RC=0
exit /b 0

:ts
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH-mm-ss'"`) do set "_TS=%%A"
exit /b 0

:usage
echo Uzycie:
echo   run_insert_pytest.bat ^<KONTO^> ^<YYYY-MM-DD^> [LAYOUT]
echo Domyslny LAYOUT: positions-pl ^(Raport Historii MT5, mapowanie: docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md^)
echo Opcja: deals-default ^(auto-HTML z ExportDailyHistoryHtml^)
echo.
echo Przyklady:
echo   run_insert_pytest.bat 10827887 2026-03-18
echo   run_insert_pytest.bat 10827887 2026-03-18 deals-default
if "%IS_INTERACTIVE%"=="1" pause
exit /b 1

:fail_python
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b !RC!

:fail2
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b 2

:fail3
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b 3

:fail4
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b 4

:fail5
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b 5

:fail6
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b 6

:fail7
echo [INFO] Szczegoly: "%LOGFILE%"
if "%IS_INTERACTIVE%"=="1" pause
exit /b 7
