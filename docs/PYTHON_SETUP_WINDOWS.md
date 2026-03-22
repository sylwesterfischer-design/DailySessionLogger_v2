# Python 3 na Windows (naprawa CSV + skrypt INSERT)

Potrzebne do:

- `scripts/csv_repair_horizontal_summary/repair_daily_session_summary.py`
- `scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py`

**Jeśli `.msix` się sypie** (błąd rejestru, App Installer) — spróbuj **`python-manager-*.msi`** (§0, Wariant MSI) **albo** od razu **§ 1 (python.org)**. Na skrypty CSV python.org w zupełności wystarczy i zwykle ustawia PATH bez problemów.

---

## 0. Python Install Manager — `python-manager` (`.msi` / `.msix`, bez junction do Cursora)

**Junction nie jest potrzebny** i **Cursor/AI nie zainstaluje** Pythona na Twoim Windowsie — instalacja musi wykonać się **u Ciebie** (bezpieczeństwo + brak dostępu agenta do instalacji aplikacji).

### Wariant MSI — `python-manager-*.msi` (często prostszy niż `.msix`)

Ten sam **Python Install Manager** od Microsoft, ale pakiet **MSI** idzie przez **Windows Installer** (`msiexec`) — **nie** przez AppX / App Installer. U wielu osób to omija błąd **„Nieprawidłowa wartość dla Rejestru”** przy dwukliku na `.msix`.

1. Umieść plik np. w `D:\Cursor_Agent\środowisko\python-manager-26.0.msi`.
2. **Dwuklik** na `.msi` — jeśli pojawi się UAC, potwierdź (**administrator** bywa wymagany przy MSI).
3. Dokończ kreatora instalacji.
4. Potem jak zawsze przy menedżerze: **Menu Start** → **Python Install Manager** → **zainstaluj środowisko Python 3.12+** z poziomu aplikacji (sam menedżer to nie ten sam krok co interpreter w PATH).
5. **Nowe** okno PowerShell → `python --version` lub `py --version` (patrz też akapit poniżej o braku zmiennej `PYTHON`).

Z wiersza poleceń (ścieżkę dostosuj; ewentualnie uruchom PowerShell **jako administrator**):

```powershell
msiexec /i "D:\Cursor_Agent\środowisko\python-manager-26.0.msi"
```

### `WindowsApps` + brak Pythona w klasycznym **Path** — to często **aliasy**, nie błąd instalacji

Jeśli w Eksploratorze widzisz np.  
`C:\Program Files\WindowsApps\PythonSoftwareFoundation.PythonManager_... \python.exe`,  
a w oknie **Zmienne środowiskowe** nadal **nie ma** oczywistego wpisu „Python” — **może tak być**: aplikacje w stylu Sklepu / MSIX często **nie dopisują** długiej ścieżki do **Path** użytkownika, tylko uruchamiają `python` / `py` przez **aliasy wykonywania aplikacji** (App execution aliases).

**Co robić (zgodnie z pomocnikiem `py-manager.exe`):**

1. W oknie, które pyta *Open Settings now?* — wpisz **`y`** i włącz w ustawieniach odpowiednie pozycje **Python (default)** i **Python install manager** (nazwy mogą być po angielsku w interfejsie).
2. Albo ręcznie: **Ustawienia** → **Aplikacje** → **Ustawienia zaawansowane** (lub **Zaawansowane ustawienia aplikacji**) → **Aliasy wykonywania aplikacji**  
   (EN: *Settings* → *Apps* → *Advanced app settings* → *App execution aliases*).
3. Upewnij się, że przełączniki przy **python.exe** / **Python** / **Python install manager** są **Włączone** (czasem konflikt robi **inny** alias ze Sklepu — wtedy **wyłącz** zbędny wpis, który „kradnie” polecenie `python`).

**Jak sprawdzić, czy już działa (nowe okno terminala):**

```powershell
py --version
```

Jeśli `where` pokazuje ścieżkę pod `...\WindowsApps\...` lub `...\AppData\Local\Microsoft\WindowsApps\...` — **nie musisz** ręcznie nic dopisywać do Path.

**Ręczne dodanie do Path (tylko gdy aliasy nie pomagają — słabsza opcja):**

1. `Win + R` → `sysdm.cpl` → **Zaawansowane** → **Zmienne środowiskowe**.
2. W sekcji **Zmienne użytkownika** wybierz **Path** → **Edytuj** → **Nowy** → wklej **folder** (katalog), w którym leży `python.exe` (nie sam plik).  
   **Uwaga:** ścieżka w `WindowsApps` ma **wersję w nazwie** — po aktualizacji menedżera może przestać działać; **pewniejsze** jest naprawienie aliasów albo **§ 1 (python.org + Add to PATH)**.

### Wariant A — `.msix` z Eksploratora

1. Otwórz folder np. `D:\Cursor_Agent\środowisko`.
2. **Dwuklik** na `python-manager-26.0.msix` (albo prawy przycisk → **Otwórz**).
3. Jeśli Windows pyta o zaufanie do aplikacji — potwierdź (to menedżer instalacji Pythona od Microsoft).
4. Po instalacji **Python Install Manager** (lub podobna aplikacja) powinien pojawić się w Menu Start — uruchom go i **doinstaluj środowisko Python 3.12+** z poziomu tej aplikacji (postępuj wg ekranów).

### Wariant B — PowerShell (gdy dwuklik nie działa)

Otwórz **PowerShell** jako zwykły użytkownik:

```powershell
cd "D:\Cursor_Agent\środowisko"
dir *.msix
Add-AppxPackage -Path ".\python-manager-26.0.msix"
```

Albo przeciągnij plik `.msix` z Eksploratora do okna PowerShell — wstawi się poprawna ścieżka.

Jeśli pojawi się błąd o **niezaufanej aplikacji** / **sideloading** — przejdź od razu do **§ 1 (python.org)**.

### Wariant B2 — błąd przy dwukliku: „Nieprawidłowa wartość dla Rejestru”

To znany problem Windows z **obsługą pakietów MSIX / App Installer**, a nie z samym plikiem projektu.

**Co zrobić (od najprostszego):**

1. **Zignoruj MSIX** i zainstaluj Pythona z **[python.org](https://www.python.org/downloads/windows/)** — **§ 1** poniżej (**Add python.exe to PATH**). To **wystarczy** do `repair` / `insert`.
2. Opcjonalnie: Microsoft Store → zaktualizuj aplikację **App Installer** (instaluje i aktualizuje `.msix`).
3. Opcjonalnie (zaawansowane): uruchom w cmd jako admin `wsreset` (reset Sklepu) — tylko jeśli wiesz, po co; potem ponów próbę MSIX.

**Nie trzeba** naprawiać rejestru ręcznie tylko po to, żeby uruchomić nasze skrypty — **python.org jest szybszą drogą**.

### Po `Add-AppxPackage` widzę PROCESSING — czy Python jest już zainstalowany? Gdzie jest PYTHON w zmiennych?

**To dwie różne rzeczy:**

1. **Sukces MSIX (`PROCESSING` bez błędu)** zwykle oznacza: zainstalowała się aplikacja **Python Install Manager** (menedżer od Microsoft), a **nie** koniecznie od razu pełny interpreter z wpisem w klasycznym **Path**, jak po instalatorze z python.org.
2. **Zmiennej o nazwie `PYTHON` Windows i tak zwykle nie tworzy** — to normalne. Do działania w terminalu liczy się:
   - wpisy w **`Path`** (np. folder `...\Python312\` i czasem `...\Python312\Scripts\`), **albo**
   - **Python Launcher** (`py.exe` z Microsoft Store — często jest w `...\WindowsApps\`).

**Co zrobić po udanym MSIX:**

1. Otwórz **Menu Start** i wyszukaj **Python Install Manager** (lub podobną nazwę) — uruchom i **z poziomu tej aplikacji zainstaluj środowisko Python 3.12+** (krok, który MSIX sam z siebie nie zastępuje).
2. **Zamknij wszystkie** okna PowerShell / Cursor i otwórz **nowe** (PATH ładuje się przy starcie procesu).
3. W nowym PowerShell sprawdź:

```powershell
python --version
py --version
```

Jeśli któreś działa — **środowisko pod nasze skrypty jest OK** (nie musisz widzieć osobnej zmiennej `PYTHON` w oknie „Zmienne środowiskowe”).

Jeśli **obydwa** zgłaszają brak polecenia — albo dokończ instalację w menedżerze, albo przejdź na **§ 1 / Wariant C (python.org + Add to PATH)** — to najpewniejsze pod `python` w PATH.

### Wariant C — bez MSIX: klasyczny instalator (najpewniejszy pod PATH)

1. [python.org/downloads](https://www.python.org/downloads/windows/) → **Python 3.12+** → installer 64-bit.
2. Na pierwszym ekranie zaznacz **Add python.exe to PATH**.
3. Zakończ instalację.

Po dowolnym wariancie: **zamknij i otwórz ponownie** PowerShell / Cursor, potem `python --version`.

---

## 1. Instalacja (klasyczna — jeśli nie używasz MSIX)

1. Wejdź na [python.org/downloads](https://www.python.org/downloads/windows/) i pobierz **Python 3.12+** (Windows installer 64-bit).
2. Uruchom instalator i **zaznacz** na pierwszym ekranie: **„Add python.exe to PATH”** / **„Dodaj Pythona do PATH”**.
3. Dokończ instalację (domyślne opcje są OK).

## 2. Sprawdzenie (PowerShell)

```powershell
python --version
```

Jeśli `nie znaleziono Python` — zamknij i otwórz ponownie PowerShell / Cursor (odświeżenie PATH).  
Opcjonalnie użyj **„Python Launcher”**:

```powershell
py --version
```

Wtedy zamiast `python` w poleceniach wpisuj `py` (np. `py scripts\...`).

**Skąd bierze się `python` (diagnoza):**

```powershell
where.exe python
where.exe py
```

Gdy nadal pusto — wróć do §0 (*Aliasy wykonywania aplikacji*) albo do **§ 1 (python.org)**.

**Path i junctiony (skrypty z tego repozytorium):** jeśli **`py --version`** działa — **nie musisz** dopisywać Pythona do **Path** (chyba że wolisz pisać `python` i wyłączysz stuby Sklepu jak wyżej). **Junctionów nie trzeba** — w terminalu wykonaj `cd` do katalogu `DailySessionLogger_v2` i uruchamiaj skrypty ścieżkami jak poniżej; zamień **`python`** na **`py`**, gdy u Ciebie działa tylko launcher.

## 3. Naprawa `DailySessionSummary.csv` (bez Notepad++)

Najpierw **`--dry-run`** (nic nie zapisuje), potem z backupem:

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"

py scripts/csv_repair_horizontal_summary/repair_daily_session_summary.py `
  -i "$env:APPDATA\MetaQuotes\Terminal\Common\Files\DailySessionSummary.csv" `
  --only-date 2026-03-20 --only-konto 11693814 --backup
```

**Nie trzeba** ręcznie czyścić w Notepad++ — skrypt naprawia strukturę pól.

## 4. INSERT z HTML (przykład z Raportem Historii PL — Pozycje)

```powershell
cd "...DailySessionLogger_v2"

py scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py `
  --layout positions-pl `
  --html "reports_10828174\ReportHistory-10828174.html" `
  --konto 10828174 `
  --deals-in "data\DailySessionDeals10828174.csv" `
  --dry-run
```

Duży plik HTML może chwilę trwać. Bez `--dry-run` powstanie np. `DailySessionDeals10828174_INSERT.csv` obok wejściowego CSV (lub ustaw `--deals-out`).

**Mapowanie kolumn HTML → CSV (Pozycje PL), rola `deal_ticket`:**  
`docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md` — tabela z załączonego arkusza, wyjaśnienie **dlaczego skrypt musi mieć klucz jak `deal_ticket`** (deduplikacja), oraz kiedy **Pozycja = `deal_ticket`** wystarczy zamiast raportu Deals.
