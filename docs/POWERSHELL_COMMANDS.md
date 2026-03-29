# PowerShell / CMD — gotowce (Git, Cursor, junctiony)

**Ten dokument nie zmienia schematu** plików CSV EA — to **ściąga komend** z podziałem na **co do czego służy**.

**Środowisko:** komendy poniżej zakładają **Windows** + **PowerShell** (lub **cmd** przy `mklink`), chyba że napisano inaczej.

**Utrzymanie:** każda **nowa**, powtarzalna komenda przekazana w pracy z tym repo ma tu trafić (opis + przykład) — **§1d.8** w `.cursorrules_General`.

---

## Skorowidz komend (nazwa → składnia → cel → gdzie → przykład)

| Nazwa (skrót) | Składnia (rdzeń) | Do czego służy | Gdzie uruchomić | Gotowy przykład / sekcja |
|---------------|------------------|----------------|-----------------|---------------------------|
| **Wejście do repo** | `cd "…\DailySessionLogger_v2"` | Stały katalog roboczy pod `git` / skrypty | PowerShell | Zob. każdą sekcję `[GIT]` |
| **Status Git (krótki)** | `git status -sb` | Czy są zmiany / branch vs `origin` | PowerShell, **root repo** | `[GIT]` |
| **Historia → plik** | `git log -8 --oneline --decorate \| Tee-Object -FilePath ".\git_snapshot.txt"` | Log do pliku (jeden `-FilePath`!) | PowerShell, **root repo** | `[GIT]` |
| **Diff `.mq5` vs HEAD** | `git diff HEAD -- DailySessionLogger_v2.mq5` | Czy lokalny EA różni się od ostatniego commita | PowerShell, **root repo** | `[GIT]` |
| **Remote / push** | `git remote -v` / `git push -u origin main` | Połączenie z GitHubem i wypchnięcie | PowerShell, **root repo** | `[GIT]` |
| **Tożsamość Git** | `git config --global user.email "…"` / `user.name` | Autor commitów | PowerShell (raz na PC) | `[GIT]` |
| **Python manager (.msix)** | `Add-AppxPackage -Path "…python-manager….msix"` | Środowisko Python pod `py` / skrypty | PowerShell **(często Admin)** | `[CURSOR / ŚRODOWISKO]` |
| **Junction `reports_*` (POPRAWNY)** | `cmd /c mklink /J "%CommonFiles%\reports_<LOGIN>" "<repo>\reports_<LOGIN>"` | HTML z **`ExportDailyHistoryHtml`** → widok w repo (**`Common\Files`**) | cmd lub PowerShell wywołujące `cmd /c` | `[JUNCTION — reports_*]` — **nie** `MQL5\Reports` |
| **Junction `logs_*`** | `New-Item -ItemType Junction -Path ".\logs_<LOGIN>" -Target "…\<HASH>\MQL5\Logs"` | Logi MT5 w workspace | PowerShell, **root repo** | `[JUNCTION — logs_*]` |
| **Junction `scripts_*`** | `New-Item -ItemType Junction -Path ".\scripts_<LOGIN>" -Target "…\<HASH>\MQL5\Scripts"` | Skrypty `.mq5` w terminalu widoczne w repo | PowerShell, **root repo** | `[JUNCTION — scripts_*]` |
| **Junction `docs\tv_scheduled` (2× MT5)** | `New-Item -ItemType Junction -Path "<drugi>\docs\tv_scheduled" -Target "<master>\docs\tv_scheduled"` | Jeden folder PNG z Playwright dla dwóch kopii `DailySessionLogger_v2` | PowerShell (Admin jeśli brak praw) | `[JUNCTION — docs\tv_scheduled]` |
| **TV zrzuty — auto po logowaniu (Win11)** | `scripts\tv_screenshot\install_scheduled_task.cmd` / `-Remove` | Harmonogram: `pythonw` + `scheduled_screenshots.py` (bez Execution Policy) | cmd / Explorer, **root repo** | `[SCHEDULED TASK — tv_screenshot]` |
| **Test junctionów (dysk)** | `.\scripts\junctions\Test-JunctionAccess.ps1` | Czy ścieżki z manifestu istnieją i dają się odczytać (§**1d.9**) | PowerShell, **root repo** | `[JUNCTION — test dostępu]` |
| **Usunięcie junctiona (tylko link)** | `cmd /c rmdir ".\scripts_<LOGIN>"` | Usuwa dowiązanie, **nie** kasuje plików w MT5 | PowerShell, **root repo** | `[JUNCTION — scripts_*]` / `logs_*` |
| **WSL 2 — domyślna wersja (bajery)** | `wsl --set-default-version 2` | Nowe dystrybucje WSL startują jako **WSL 2** | **PowerShell** (Windows, często Admin) | `[WSL / BAJERY]` |
| **Ubuntu — update (bajery)** | `sudo apt update && sudo apt upgrade` | Aktualizacja pakietów w dystrybucji pod WSL | **Bash** (terminal **Ubuntu** / WSL, nie PowerShell) | `[WSL / BAJERY]` |
| **cmatrix — deszcz Matrixa (bajery)** | `sudo apt install cmatrix` → `cmatrix` | Efekt wizualny „padające znaki” w terminalu | **Bash** (Ubuntu w WSL) | Wyjście: **q** lub **Ctrl+C** |
| **hollywood — ekran „z filmu” (bajery)** | `sudo apt install hollywood` → `hollywood` | Wiele paneli, scroll logów — styl „hackerski” | **Bash** (Ubuntu w WSL) | Po instalacji: `hollywood` |
| **Ollama (opcjonalnie)** | `ollama --version` / `irm …install.ps1 \| iex` | Lokalny LLM, niezależny od MT5 | PowerShell | `[OLLAMA — opcjonalnie]` |

### Przykład **BŁĘDNY** (nie używać dla `ExportDailyHistoryHtml`)

Źródło: typowa pomyłka z notatek — cel **`MQL5\Reports`** to **nie** folder zapisu tego EA.

```text
# ŹLE dla eksportu HTML z ExportDailyHistoryHtml:
New-Item -ItemType Junction -Path ".\reports_10827887" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\<HASH>\MQL5\Reports"
```

**Dlaczego źle:** EA zapisuje pod `%APPDATA%\MetaQuotes\Terminal\Common\Files\<InpSubfolder>\`, a nie pod `...\MQL5\Reports`. Użyj wiersza **„Junction reports_* (POPRAWNY)”** w tabeli i sekcji `[JUNCTION — reports_*]`.

---

## Legenda sekcji

| Tag | Zastosowanie |
|-----|----------------|
| **`[GIT]`** | Repozytorium, `origin`, commit, push, podgląd historii |
| **`[CURSOR / ŚRODOWISKO]`** | Python / menedżer instalacji pod skrypty i agenta (bez MT5) |
| **`[JUNCTION — reports_*]`** | HTML z **`ExportDailyHistoryHtml`** → `Common\Files\reports_<LOGIN>` |
| **`[JUNCTION — logs_*]`** | Logi MT5 → `...\Terminal\<HASH>\MQL5\Logs` (lub wariant `...\Logs`) |
| **`[JUNCTION — scripts_*]`** | Skrypty `.mq5` w terminalu → `...\Terminal\<HASH>\MQL5\Scripts` |
| **`[JUNCTION — data\]`** | Opcjonalnie: CSV EA w workspace — patrz uwaga poniżej |
| **`[OLLAMA — opcjonalnie]`** | Lokalny LLM (nie jest wymagany do Gita ani MT5) |

---

## `[GIT]` — podstawy remote i push

```powershell
# Środowisko: PowerShell, katalog = root projektu DailySessionLogger_v2
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

git remote -v
git remote add origin https://github.com/sylwesterfischer-design/DailySessionLogger_v2.git
# lub zmiana URL:
git remote set-url origin https://github.com/sylwesterfischer-design/DailySessionLogger_v2.git

git push -u origin main
```

### Tożsamość commitów (ustaw **raz** na maszynie)

```powershell
git config --global user.name "Twoja Nazwa"
git config --global user.email "twoj@email.example"
```

*(Zastąp wartości własnymi — **nie** commituj haseł ani sekretów do repo.)*

### Status + skrót historii (jedna linia wyjścia → plik)

```powershell
# Środowisko: PowerShell — jeden plik wyjścia, bez drugiego argumentu na końcu wiersza
git status -sb
git log -8 --oneline --decorate | Tee-Object -FilePath ".\git_snapshot.txt"
```

### Porównanie pliku EA z ostatnim commitem (po zapisaniu `.mq5` na dysku)

```powershell
git diff HEAD -- DailySessionLogger_v2.mq5
```

**Dalsze kroki Git:** `docs/GITHUB_SETUP_STEP_BY_STEP.md`.

---

## `[CURSOR / ŚRODOWISKO]` — Python (np. `insert_from_mt5_html.py`)

```powershell
# Środowisko: PowerShell (często jako Administrator przy pierwszej instalacji .msix)
# Ścieżkę do pliku .msix dostosuj do siebie (folder „Cursor_Agent” / Pobrane):
Add-AppxPackage -Path "D:\Cursor_Agent\srodowisko\python-manager-26.0.msix"
# Alternatywa (jeśli używasz polskiej nazwy folderu w ścieżce):
# Add-AppxPackage -Path "D:\Cursor_Agent\środowisko\python-manager-26.0.msix"
```

- Szczegóły: **`docs/PYTHON_SETUP_WINDOWS.md`** (launcher `py`, stuby Sklepu, itd.).
- **To nie jest** junction — Python działa z dowolnego `cd` do repo.

---

## `[JUNCTION — test dostępu]` — `Test-JunctionAccess.ps1` + manifest

**Po co:** indeks / `Glob` w Cursorze czasem **nie widzi** plików **wewnątrz** junctionów NTFS — skrypt sprawdza **fizyczny** dostęp (`.cursorrules_General` §**1d.9**).

**Środowisko:** PowerShell, **katalog = root** `DailySessionLogger_v2`.

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
.\scripts\junctions\Test-JunctionAccess.ps1
```

- **Manifest** (co sprawdzamy): `scripts/junctions/junctions_manifest.txt` — jedna ścieżka **względem rootu repo** na linię; puste linie i `#` ignorowane.
- **Opis junctionów:** `docs/JUNCTIONS_INVENTORY.md` — uzupełniaj przy nowych `mklink` / `New-Item -ItemType Junction`.
- **Exit code:** `0` = OK; `1` = brak ścieżki lub błąd listingu; `2` = brak pliku manifestu.

---

## `[JUNCTION — reports_*]` — raporty HTML EA (`Common\Files`)

**Po co:** `ExportDailyHistoryHtml.mq5` zapisuje do **`%APPDATA%\MetaQuotes\Terminal\Common\Files\reports_<LOGIN>\*.html`**. Junction podpinasz **zwykle** tak, żeby ten podfolder był widoczny w repo jako `reports_<LOGIN>`.

**Nie myl z `MQL5\Reports`:** to **inny** katalog (często raporty z menu MT5). Dla **tego** projektu kluczowy jest **`Common\Files\reports_*`**.

**Częsty błąd z notatek:** junction `reports_<LOGIN>` w repo **nie** powinien wskazywać na `...\MQL5\Reports` ani mieszać **dwóch różnych** profili `Terminal\<HASH>` pod **jedną** nazwą — `ExportDailyHistoryHtml` zapisuje do **`%APPDATA%\MetaQuotes\Terminal\Common\Files\<InpSubfolder>\`** (katalog **Common**), nie do `...\MQL5\Reports`.

### Wariant A — `mklink /J` (cmd; często jako Administrator)

```bat
REM Środowisko: cmd
REM Dostosuj: HASH terminala docelowego + ścieżkę repo + LOGIN

set COMMON=%APPDATA%\MetaQuotes\Terminal\Common\Files
set TARGET=C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\reports_10827887

mkdir "%TARGET%" 2>nul
mklink /J "%COMMON%\reports_10827887" "%TARGET%"
```

Jeśli **`reports_10827887`** już istnieje w `Common\Files` jako **zwykły** folder — usuń lub zmień nazwę **przed** `mklink`.

### Wariant B — PowerShell + `cmd /c mklink` (jak w `EXPORT_DAILY_HTML_JUNCTIONS.md`)

```powershell
# Środowisko: PowerShell (Administrator, jeśli system tego wymaga)
$commonFiles = "$env:APPDATA\MetaQuotes\Terminal\Common\Files"
$target      = "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\reports_10827887"
New-Item -ItemType Directory -Force -Path $target | Out-Null
cmd /c mklink /J "$commonFiles\reports_10827887" "$target"
```

**Pełny opis + ostrzeżenie „nie junctionować całego `Common\Files`”:** `docs/EXPORT_DAILY_HTML_JUNCTIONS.md`.

---

## `[JUNCTION — logs_*]` — logi MT5

**Cel junctiona:** folder w repo `logs_<LOGIN>` (lub `logs_<LOGIN>_terminal`) → **rzeczywisty** katalog logów **tej** kopii MT5.

Typowa ścieżka docelowa:

`C:\Users\<Ty>\AppData\Roaming\MetaQuotes\Terminal\<HASH>\MQL5\Logs`

*(U niektórych instalacji bywa `...\Terminal\<HASH>\Logs` — sprawdź **Plik → Otwórz folder danych** w MT5.)*

```powershell
# Środowisko: PowerShell, katalog = root projektu
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

# Przykład — ZAMIEŃ <HASH> i login:
New-Item -ItemType Junction -Path ".\logs_10827887" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\<HASH>\MQL5\Logs"
```

**Usunięcie tylko dowiązania (nie kasuje logów w terminalu):**

```powershell
cmd /c rmdir ".\logs_10827887"
```

---

## `[JUNCTION — scripts_*]` — `MQL5\Scripts` (reconcile / skrypty)

**Cel:** `scripts_<LOGIN>` w repo → `...\Terminal\<HASH>\MQL5\Scripts` **tego** profilu, na którym jesteś zalogowany na dane konto.

Gotowe przykłady i **`Create-ScriptsJunctions.ps1`:** **`docs/SCRIPTS_JUNCTIONS.md`**.

Skrót — ten sam wzorzec co logi, inny **Target**:

```powershell
New-Item -ItemType Junction -Path ".\scripts_10828174" -Target "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\<HASH>\MQL5\Scripts"
```

**Odpowiednik cmd:**

```bat
mklink /J "C:\...\DailySessionLogger_v2\scripts_10828174" "C:\Users\...\Terminal\<HASH>\MQL5\Scripts"
```

---

## `[JUNCTION — data\]` — CSV w workspace

W wielu setupach folder **`data\`** w projekcie jest **junctionem** do fragmentu **`Common\Files`** (albo innej ścieżki), żeby CSV z EA były widoczne w Cursorze.

- **Konkretną ścieżkę** masz ustalić u siebie (hash terminala + polityka plików).
- **Nigdy** nie zamieniaj całego `Common\Files` na jeden junction „na siłę” — zobacz ostrzeżenie w `EXPORT_DAILY_HTML_JUNCTIONS.md`.

---

## `[JUNCTION — docs\tv_scheduled]` — zrzuty TradingView (Playwright), dwa terminale MT5

**Problem:** masz **dwie** kopie repo pod `…\Terminal\<HASH>\MQL5\Experts\Advisors\DailySessionLogger_v2\` (inny **HASH** = inna instalacja MT5). Skrypt `scheduled_screenshots.py` zapisuje PNG tylko w **`docs\tv_scheduled`** tej kopii, z której uruchomiłeś Pythona — druga ścieżka **nie dostaje** plików automatycznie (to nie jest junction w repo domyślnie).

**Rozwiązanie:** wybierz **jeden folder „master”** (np. ten, z którego zwykle odpalasz harmonogram i gdzie jest Cursor), a w drugiej instalacji **usuń zwykły** `docs\tv_scheduled` i utwórz **junction** o tej samej nazwie wskazujący na master.

**Uwaga:** jeśli w „drugim” folderze są **unikalne** PNG, skopiuj je do mastera **zanim** usuniesz folder.

**Pojedynczo czy razem?** W **jednym** oknie PowerShell możesz **wkleić cały blok naraz** (Enter na końcu) — zmienne `$master` / `$link` zostaną ustawione i kolejne linie zadziałają w tej samej sesji. Możesz też wpisywać **linia po linii** — byle **nie zamykać** okna między krokami. Nowe okno = musisz od nowa zdefiniować `$master` i `$link`.

**Częsty błąd:** `New-Item -ItemType Junction` zgłasza, że **nie ma** folderu **docelowego** (`$master`). Junction wymaga, żeby **target** już fizycznie istniał. Najpierw sprawdź, czy w ogóle masz folder `…\DailySessionLogger_v2\` pod wybranym HASHEM (`Test-Path` na katalog nadrzędny). Jeśli hash `49C33…` nie istnieje na tym PC (inna instalacja MT5), **zamień** miejscami: **master** = katalog, który **jest**, **link** = drugi.

### Przykład (Twoje hashe z rozmowy)

- **Master (źródło):** `49C33A939697AEF354FFC02653AB58DE`
- **Drugi terminal:** `0E812ED0A250D901020B93B704737346`

```powershell
# 0) Ustaw ścieżki (dopasuj HASH, jeśli u Ciebie inne)
$master = 'C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\docs\tv_scheduled'
$link   = 'C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\0E812ED0A250D901020B93B704737346\MQL5\Experts\Advisors\DailySessionLogger_v2\docs\tv_scheduled'

# 1) Repo pod masterem musi istnieć — inaczej junction się nie uda
$repoMaster = Split-Path (Split-Path $master -Parent) -Parent
if (-not (Test-Path -LiteralPath $repoMaster)) {
  Write-Error "Brak folderu repo: $repoMaster — zmień `$master` na istniejącą kopie DailySessionLogger_v2 (inny HASH terminala)."
  return
}

# 2) Utwórz master (całe drzewo katalogów); potem weryfikacja
[void][System.IO.Directory]::CreateDirectory($master)
if (-not (Test-Path -LiteralPath $master)) { Write-Error "Nie utworzono: $master"; return }

# 3) Usuń stary $link (zwykły folder), żeby zrobić junction o tej nazwie
if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Recurse -Force }

# 4) Junction: Path = link, Target = master (oba muszą być pełnymi ścieżkami)
New-Item -ItemType Junction -Path $link -Target $master

# 5) Walidacja
Get-Item -LiteralPath $link | Format-List FullName, Attributes, LinkType, Target
```

**Dlaczego „mało zrzutów”:** nowe PNG pojawiają się tylko gdy **działa** `scheduled_screenshots.py` (lub ręcznie `screenshot_tv.py`). Harmonogram nie jest usługą systemową — po zamknięciu okna / wylogowaniu / uśpieniu bez procesu w tle **nie ma** nowych plików. Przy 6 jobach (M1…H4) w krótkim teście zobaczysz tylko kilka plików z pierwszego cyklu.

---

## `[SCHEDULED TASK — tv_screenshot]` — zrzuty TradingView w tle (Windows 11)

To **zadanie harmonogramu** (Task Scheduler) dla bieżącego użytkownika, **nie** wpis w `services.msc`. **Wyzwalacz:** przy **logowaniu**. **Akcja:** `.venv\Scripts\pythonw.exe` + argument `scripts\tv_screenshot\scheduled_screenshots.py` (katalog roboczy = root repo). **Ustawienia:** brak limitu czasu wykonania, jedna instancja (`IgnoreNew`), ponowny start przy błędzie (3×, co 1 min).

**Instalacja (zalecane):** plik **`scripts\tv_screenshot\install_scheduled_task.cmd`** — wywołuje `powershell.exe` z **`%SystemRoot%\System32\WindowsPowerShell\v1.0\`**, więc działa bez `powershell` w PATH i bez ręcznego zezwalania na `.ps1`. Uruchom z rootu repo lub dwuklik w Eksploratorze.

```bat
cd "C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<HASH>\MQL5\Experts\Advisors\DailySessionLogger_v2"
scripts\tv_screenshot\install_scheduled_task.cmd
```

**Instalacja (PowerShell):** jeśli `.ps1` jest zablokowany — `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force`, potem `.\scripts\tv_screenshot\install_scheduled_task.ps1`. Albo: `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File "...\install_scheduled_task.ps1"`.

**Odinstalowanie:**

```powershell
.\scripts\tv_screenshot\install_scheduled_task.ps1 -Remove
```

**Start od ręki:** `Start-ScheduledTask -TaskName 'DailySessionLogger_TV_Screenshots'`  
**Zatrzymanie procesu:** Menedżer zadań → `pythonw.exe` (ścieżka z `.venv\Scripts\`) lub `Stop-ScheduledTask -TaskName 'DailySessionLogger_TV_Screenshots'`

Szczegóły i ograniczenia (sen, logowanie): **`scripts/tv_screenshot/README.md`** — sekcja „Automatycznie po starcie Windows 11”. **Logi (`tv_capture.log` vs `tv_save_session.log`):** **`docs/TV_SCREENSHOT_LOGGING.md`**.

---

## `mklink /J` vs `New-Item -ItemType Junction`

| Metoda | Składnia (idea) |
|--------|------------------|
| **cmd** | `mklink /J "<link>" "<cel>"` — **link** = nazwa junctiona (np. w `Common\Files`), **cel** = folder docelowy (np. w repo). |
| **PowerShell** | `New-Item -ItemType Junction -Path "<link>" -Target "<cel>"` — przy tworzeniu **w repo** często `Path` = `.\scripts_LOGIN`, `Target` = `...\MQL5\Scripts`. |

Kierunek zależy od tego, **co** podpinasz: dla **reports** z dokumentacji EA często junction **w Common** wskazuje na folder **w repo**; dla **scripts/logs** często junction **w repo** wskazuje na folder **w Terminal\<HASH>**.

---

## `[WSL / BAJERY]` — WSL 2 + Ubuntu: wizualne „zabawne” narzędzia

**To nie jest** PowerShell — wymaga **WSL** (np. Ubuntu z Microsoft Store). W tabeli skorowidza oznaczone jako **„bajery”**.

### Windows — ustawienie domyślnej wersji WSL 2

```powershell
# Środowisko: PowerShell (Windows; często uruchom jako Administrator)
wsl --set-default-version 2
```

### Ubuntu (wewnątrz WSL) — aktualizacja systemu

```bash
# Środowisko: Bash — terminal „Ubuntu” (WSL), NIE PowerShell
sudo apt update && sudo apt upgrade
```

- **`sudo`** — polecenia jako administrator w Linuxie; przy wpisywaniu hasła **nie widać** gwiazdek — to normalne.
- Potwierdzaj instalacje **Enter** / **T** (Tak), zależnie od pytania `apt`.

### Instalacja i uruchomienie efektów (bajery)

```bash
# Środowisko: Bash (Ubuntu w WSL)
sudo apt install cmatrix
cmatrix
# Wyjście z cmatrix: klawisz q lub Ctrl+C

sudo apt install hollywood
hollywood
```

**Uwaga:** jeśli po restarcie nie widzisz aplikacji Ubuntu — sprawdź, czy WSL jest zainstalowany i włączony (dokumentacja Microsoftu: WSL / Ubuntu).

---

## `[OLLAMA — opcjonalnie]` — lokalny model (nie Git, nie MT5)

```powershell
# Środowisko: PowerShell
ollama --version

# Instalacja (oficjalny skrypt — ocena ryzyka jak każdy remote script):
irm https://ollama.com/install.ps1 | iex

# Serwer (jedno okno konsoli):
# cd <folder z ollama>
# .\ollama serve

# Modele (drugie okno):
# ollama pull qwen2.5:14b
# ollama run qwen2.5-coder:14b
```

To **nie** konfiguruje Cursor Agent w pełni — to tylko lokalny backend, jeśli z niego korzystasz.

---

## Aktualizacja

Po zmianie **HASH** terminala lub przeniesieniu repo — przepisz ścieżki w swoich notatkach lokalnych; ten plik trzymaj jako **szablon** z placeholderami `<HASH>`.
