@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM Log do pliku bez bufora (stdout Pythona od razu widoczny w run_insert_PRE_last.log)
REM run_insert_PRE_last.log: nadpisywany na poczatku kazdego uruchomienia (ostatni run); linie z BAT maja znacznik YYYY-MM-DD HH-mm-ss — patrz docs/Loggers.md
set "PYTHONUNBUFFERED=1"
set "IS_INTERACTIVE=0"
REM Opcjonalnie przed uruchomieniem: set NOPAUSE=1 — pominie pause na koncu (np. automatyzacja)
if defined NOPAUSE echo [WARN] NOPAUSE jest ustawione — na koncu sukcesu okno zamknie sie bez "Nacisnij Enter".
set "LOGFILE=%~dp0run_insert_PRE_last.log"
call :ts
> "%LOGFILE%" echo !_TS! [START] run_insert_PRE.bat
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] CWD=%CD%

REM ============================================================
REM PREVIEW + INSERT wrapper pod 2x klik:
REM   Krok A: dry-run
REM   Krok B: zapis *_INSERT.csv
REM   Krok C (opcjonalnie): nadpisanie produkcyjnych CSV
REM Uzycie:
REM   run_insert_PRE.bat <KONTO> <YYYY-MM-DD> [LAYOUT]
REM ============================================================

if "%~1"=="" (
  set "IS_INTERACTIVE=1"
  set /p KONTO=Podaj KONTO ^(np. 10827887^): 
  set /p ONLY_DATE=Podaj ONLY_DATE ^(YYYY-MM-DD^): 
  set "LAYOUT=positions-pl"
) else (
  if "%~2"=="" goto :usage
  set "KONTO=%~1"
  set "ONLY_DATE=%~2"
  set "LAYOUT=%~3"
  if "%LAYOUT%"=="" set "LAYOUT=positions-pl"
)

REM --- Walidacja konta (cyfry) ---
for /f "delims=0123456789" %%A in ("%KONTO%") do (
  echo [ERROR] Konto musi byc liczba: "%KONTO%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Konto invalid: %KONTO%
  goto :fail2
)

REM --- Walidacja daty YYYY-MM-DD ---
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
>> "%LOGFILE%" echo !_TS! [ERROR] Date invalid: %ONLY_DATE%
goto :fail2

:date_ok
set "SCRIPT_REL=scripts\csv_insert_from_mt5_html\insert_from_mt5_html.py"
if not exist "%SCRIPT_REL%" (
  echo [ERROR] Nie znaleziono "%SCRIPT_REL%".
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing script: %SCRIPT_REL%
  goto :fail3
)

REM --- Konwencje sciezek projektu ---
set "REPORTS_DIR=reports_%KONTO%"
set "HTML_PRIMARY=%REPORTS_DIR%\ReportHistory-%KONTO%.html"
set "DEALS_IN=%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionDeals%KONTO%.csv"
set "SUMMARY_IN=%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionSummary.csv"
set "DEALS_INSERT=%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionDeals%KONTO%_INSERT.csv"
set "SUMMARY_INSERT=%APPDATA%\MetaQuotes\Terminal\Common\Files\DailySessionSummary_INSERT.csv"

if not exist "%REPORTS_DIR%\" (
  echo [ERROR] Brak folderu "%REPORTS_DIR%\".
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing reports dir: %REPORTS_DIR%
  goto :fail4
)
if not exist "%DEALS_IN%" (
  echo [ERROR] Brak pliku deals-in: "%DEALS_IN%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing deals csv: %DEALS_IN%
  goto :fail5
)
if not exist "%SUMMARY_IN%" (
  echo [ERROR] Brak pliku summary-in: "%SUMMARY_IN%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing summary csv: %SUMMARY_IN%
  goto :fail6
)

REM --- Wykrycie HTML ---
set "HTML_PATH="
if exist "%HTML_PRIMARY%" (
  set "HTML_PATH=%HTML_PRIMARY%"
) else (
  for /f "delims=" %%F in ('dir /b /a:-d "%REPORTS_DIR%\ReportHistory*%KONTO%*.htm*" 2^>nul') do (
    if not defined HTML_PATH set "HTML_PATH=%REPORTS_DIR%\%%F"
  )
)
if not defined HTML_PATH (
  echo [ERROR] Nie znaleziono HTML w "%REPORTS_DIR%\".
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing html in %REPORTS_DIR%
  goto :fail7
)

echo [INFO] Konto      : %KONTO%
echo [INFO] Only date  : %ONLY_DATE%
echo [INFO] Layout     : %LAYOUT%
echo [INFO] HTML       : %HTML_PATH%
echo [INFO] Deals in   : %DEALS_IN%
echo [INFO] Summary in : %SUMMARY_IN%
echo.
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] Konto=%KONTO% Date=%ONLY_DATE% Layout=%LAYOUT% HTML=%HTML_PATH%

REM --- Krok A: Preview (dry-run) ---
REM Stdout (podsumowania) idzie do logu; stderr (pasek postepu tqdm / komunikaty) — w konsoli.
call :log_step "========================= Krok A: dry-run =============================="
echo [STEP A] Preview dry-run...
echo [HINT] Pasek postepu parsowania HTML widzisz ponizej ^(stderr^); szczegoly tekstowe tez w "%LOGFILE%".
call :utc_ms _T0_MS
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] --- Python stdout (Krok A dry-run) — linie z Pythona bez znacznika czasu z BAT; pelne timestampy: logging w skrypcie ---
py "%SCRIPT_REL%" ^
  --layout "%LAYOUT%" ^
  --html "%HTML_PATH%" ^
  --konto "%KONTO%" ^
  --summary-in "%SUMMARY_IN%" ^
  --only-date "%ONLY_DATE%" ^
  --deals-in "%DEALS_IN%" ^
  --qa-report ^
  --dry-run >> "%LOGFILE%"
set "RC=!ERRORLEVEL!"
call :utc_ms _T1_MS
call :elapsed_between _T0_MS _T1_MS _ELAPSED_A
call :ts
>> "%LOGFILE%" echo !_TS! [ELAPSED] Krok A dry-run elapsed_sec=!_ELAPSED_A! RC=!RC!
echo [ELAPSED] Krok A dry-run elapsed_sec=!_ELAPSED_A! s RC=!RC!
if not "!RC!"=="0" (
  set "FAIL_CTX=Krok A dry-run"
  echo [ERROR] Krok A nieudany ^(RC=!RC!, elapsed_sec=!_ELAPSED_A! s^).
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] StepA failed RC=!RC! elapsed_sec=!_ELAPSED_A!
  call :ts
  >> "%LOGFILE%" echo !_TS! [HINT] Sprawdz stderr w oknie CMD oraz tresc Pythona wyzej w tym logu.
  goto :fail_python
)
call :ts
>> "%LOGFILE%" echo !_TS! [OK] StepA Python RC=!RC! elapsed_sec=!_ELAPSED_A!
echo [OK] Krok A: Python RC=!RC! ^(0 = sukces, dry-run bez zapisu *_INSERT.csv^).
echo [OK] Krok A zakonczony. Szczegoly: "%LOGFILE%"
set "FAIL_CTX="
echo.
echo UWAGA: Dry-run NIE tworzy plikow _INSERT.csv — to tylko podglad.
echo        Krok B: wybierz T ^(tak^) lub N ^(nie^) — nie uzywamy tu znaku * w pytaniu ^(CMD moglby rozwinac wildcard^).
echo.
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] Po Kroku A pliki _INSERT.csv jeszcze nie istnieja ^(dry-run^). Krok B zapisze: "%DEALS_INSERT%" oraz "%SUMMARY_INSERT%"

echo.
echo [PYTANIE] Uruchomic KROK B ^(zapis plikow INSERT do Common^)?
choice /C TN /M "T = Tak, zapisz INSERT / N = Nie, zatrzymaj po preview"
REM choice: T=ERRORLEVEL 1, N=ERRORLEVEL 2 — NIE uzywac set "X=!ERRORLEVEL!" (w delayed expansion bywa zle odczytywane)
if errorlevel 2 goto :stepb_skip
call :ts
>> "%LOGFILE%" echo !_TS! [PROMPT] StepB: wybrano T — uruchamiam Krok B (Python bez --dry-run^)

REM --- Krok B: Zapis *_INSERT.csv ---
call :log_step "========================= Krok B: zapis *_INSERT.csv ================="
echo [STEP B] Generowanie plikow *_INSERT.csv...
call :utc_ms _T0_MS
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] --- Python stdout (Krok B zapis) — linie z Pythona bez znacznika czasu z BAT ---
py "%SCRIPT_REL%" ^
  --layout "%LAYOUT%" ^
  --html "%HTML_PATH%" ^
  --konto "%KONTO%" ^
  --summary-in "%SUMMARY_IN%" ^
  --only-date "%ONLY_DATE%" ^
  --deals-in "%DEALS_IN%" ^
  --deals-out "%DEALS_INSERT%" ^
  --summary-out "%SUMMARY_INSERT%" ^
  --qa-report >> "%LOGFILE%"
set "RC=!ERRORLEVEL!"
call :utc_ms _T1_MS
call :elapsed_between _T0_MS _T1_MS _ELAPSED_B
call :ts
>> "%LOGFILE%" echo !_TS! [ELAPSED] Krok B zapis INSERT elapsed_sec=!_ELAPSED_B! RC=!RC!
echo [ELAPSED] Krok B elapsed_sec=!_ELAPSED_B! s RC=!RC!
if not "!RC!"=="0" (
  set "FAIL_CTX=Krok B zapis *_INSERT.csv"
  echo [ERROR] Krok B nieudany ^(RC=!RC!, elapsed_sec=!_ELAPSED_B! s^).
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] StepB failed RC=!RC! elapsed_sec=!_ELAPSED_B!
  call :ts
  >> "%LOGFILE%" echo !_TS! [HINT] Sprawdz stderr w oknie CMD oraz tresc Pythona wyzej w tym logu.
  goto :fail_python
)
call :ts
>> "%LOGFILE%" echo !_TS! [OK] StepB Python RC=!RC! elapsed_sec=!_ELAPSED_B!
echo [OK] Krok B: Python RC=!RC! ^(0 = sukces, pliki *_INSERT.csv zapisane jesli byly wiersze^).
set "FAIL_CTX="

echo [OK] Wygenerowano:
echo [OUT] "%DEALS_INSERT%"
echo [OUT] "%SUMMARY_INSERT%"

REM --- Krok C: Opcjonalne nadpisanie produkcji ---
call :log_step "=========================Krok C (opcjonalnie): nadpisanie produkcyjnych CSV ================="
echo [STEP C] Nadpisanie produkcyjnych CSV w Common\Files — wczesniej zrob backup.
echo.
choice /C TN /M "Nadpisac produkcyjne CSV w Common? T=Tak N=Nie"
if errorlevel 2 goto :stepc_skip
call :ts
>> "%LOGFILE%" echo !_TS! [PROMPT] StepC: wybrano T — nadpisanie produkcyjnych CSV

if not exist "%DEALS_INSERT%" (
  echo [ERROR] Brak pliku insert: "%DEALS_INSERT%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing deals insert: %DEALS_INSERT%
  goto :fail8
)
if not exist "%SUMMARY_INSERT%" (
  echo [ERROR] Brak pliku insert: "%SUMMARY_INSERT%"
  call :ts
  >> "%LOGFILE%" echo !_TS! [ERROR] Missing summary insert: %SUMMARY_INSERT%
  goto :fail9
)

copy /Y "%DEALS_INSERT%" "%DEALS_IN%" >nul
if errorlevel 1 (
  echo [ERROR] Nie udalo sie podmienic deals production.
  goto :fail10
)
copy /Y "%SUMMARY_INSERT%" "%SUMMARY_IN%" >nul
if errorlevel 1 (
  echo [ERROR] Nie udalo sie podmienic summary production.
  goto :fail11
)

echo [OK] Nadpisano produkcyjne pliki:
echo      "%DEALS_IN%"
echo      "%SUMMARY_IN%"
call :ts
>> "%LOGFILE%" echo !_TS! [OK] Production overwrite done.
goto :success_exit

:stepc_skip
echo [INFO] Bez nadpisania produkcji. Koniec.
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] StepC skipped — no production overwrite
goto :success_exit

:stepb_skip
echo [INFO] Zatrzymano po preview ^(wybrano N^).
call :ts
>> "%LOGFILE%" echo !_TS! [INFO] StepB skipped by user (N)
goto :success_exit

REM --- Koniec bez bledu: RC widoczny, okno nie zamyka sie bez Enter (chyba NOPAUSE=1) ---
:success_exit
call :ts
>> "%LOGFILE%" echo !_TS! [END] run_insert_PRE.bat final_RC=0
echo.
echo ===============================================================================
echo [OK] Koniec: ostatni Python zakonczyl sie RC=0 ^(sukces^).
echo      Kroku A: „Dry-run: brak zapisu plikow” w logu = zamierzone — nie blad, nie „root-cause” awarii.
echo ===============================================================================
if defined NOPAUSE exit /b 0
echo.
echo Nacisnij Enter aby zamknac to okno...
pause
exit /b 0

REM --- Wypisz ten sam naglowek etapu do konsoli i do logu ---
:log_step
echo %~1
call :ts
>> "%LOGFILE%" echo !_TS! %~1
exit /b 0

REM Znacznik czasu dla linii logu (lokalny czas): YYYY-MM-DD HH-mm-ss — patrz docs/Loggers.md
:ts
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH-mm-ss'"`) do set "_TS=%%A"
exit /b 0

REM %~1 = nazwa zmiennej na wynik: milisekundy UTC od epoki (int)
:utc_ms
for /f "delims=" %%t in ('powershell -NoProfile -Command "[int64](Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalMilliseconds"') do set "%~1=%%t"
exit /b 0

REM %~1 %~2 = nazwy zmiennych start/koniec ms; %~3 = zmienna wyjsciowa: sekundy (3 miejsca po przecinku) lub n/a
:elapsed_between
set "PRE_D0=!%~1!"
set "PRE_D1=!%~2!"
for /f "delims=" %%e in ('powershell -NoProfile -Command "if ([string]::IsNullOrEmpty($env:PRE_D0) -or [string]::IsNullOrEmpty($env:PRE_D1)) { 'n/a' } else { [math]::Round(([int64]$env:PRE_D1-[int64]$env:PRE_D0)/1000.0,3).ToString([cultureinfo]::InvariantCulture) }"') do set "%~3=%%e"
set "PRE_D0="
set "PRE_D1="
exit /b 0

:usage
echo Uzycie:
echo   run_insert_PRE.bat ^<KONTO^> ^<YYYY-MM-DD^> [LAYOUT]
echo Przyklad:
echo   run_insert_PRE.bat 10827887 2026-03-18
if not defined NOPAUSE (
  echo Nacisnij Enter aby zamknac...
  pause
)
exit /b 1

REM UWAGA: przed goto ustaw RC=!ERRORLEVEL! oraz opcjonalnie FAIL_CTX (Krok A/B).
:fail_python
if not defined RC set "RC=1"
echo.
echo ===============================================================================
if defined FAIL_CTX (
  echo [ERROR] !FAIL_CTX! — Python RC=!RC!
) else (
  echo [ERROR] Python — RC=!RC!
)
echo         Log: "%LOGFILE%"
echo ===============================================================================
call :ts
>> "%LOGFILE%" echo !_TS! [ERROR] fail_python RC=!RC! context=!FAIL_CTX!
if not defined NOPAUSE (
  echo Nacisnij Enter aby zamknac...
  pause
)
exit /b !RC!

:fail2
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 2

:fail3
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 3

:fail4
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 4

:fail5
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 5

:fail6
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 6

:fail7
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 7

:fail8
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 8

:fail9
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 9

:fail10
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 10

:fail11
echo [INFO] Szczegoly: "%LOGFILE%"
if not defined NOPAUSE ( echo Nacisnij Enter... & pause )
exit /b 11
