# Loggers — polityka logowania (DailySessionLogger_v2)

Ten dokument jest **źródłem prawdy** dla: warstw logowania w projekcie, formatów czasu, plików `*_last.log` z launcherów BAT oraz wzorców w **Pythonie** i **MQL5**.

## Obowiązek utrzymania dokumentu

- **Ilekroć** zmienia się polityka logowania, dochodzą nowe pliki logów, nowe znaczniki lub nowe konwencje (np. BAT, Python, EA) — **należy zaktualizować ten plik** (`docs/Loggers.md`) w tej samej zmianie (commit / PR).
- Reguła dla AI / maintainerów: **`.cursorrules_CodingImprovment`** (sekcja *Logowanie — dokumentacja i spójność*).
- Reguły **wdrożenia** skryptów MQ5 (junction, `F7`, `*.ex5`) są w **`.cursorrules_Scripts`** — **nie** definiują osobnego „systemu logów”; skrypt uruchomiony z MT5 także pisze przez `Print` do tego samego kanału co EA (poniżej).

---

## Warstwy logowania — przegląd

| Warstwa | Mechanizm | Gdzie widać wynik | Uwagi |
|--------|-----------|-------------------|--------|
| **1 — EA** `DailySessionLogger_v2.mq5` | `Print`, `PrintFormat`, `Alert`, `SendNotification` | Zakładka **Eksperci** w terminalu; pliki tekstowe **`MQL5\Logs\*.log`** (profil `Terminal\<hash>\`) | Główny dziennik zachowania EA i zapisów CSV |
| **2 — Skrypty** `MQL5\Scripts\*.mq5` (np. reconcile) | `Print` (jak wyżej) | Jak warstwa 1 | Wdrożenie: `.cursorrules_Scripts` |
| **3 — Python** (CLI w `scripts\`) | `print()` → **stdout** / **stderr** (`sys.stderr`, `tqdm`) | Konsola; przy launcherze BAT także plik `*_last.log` (stdout) | Domyślnie **bez** modułu `logging` — patrz *Wersja A* poniżej |
| **4 — BAT** `run_insert_PRE.bat`, `run_insert_pytest.bat` | `echo`, `choice`, `:ts`, przekierowania | Konsola + **`run_insert_*_last.log`** w katalogu projektu | Stdout Pythona **bez** prefiksu czasu BAT na każdej linii |

**Powiązanie z `.cursorrules_Scripts`:** dotyczy **ścieżek**, kompilacji i kopii do `scripts_<LOGIN>` — logi skryptów to nadal **Print → Experts / MQL5\Logs**, tak jak w tabeli.

---

## Dwa wzorce referencyjne (format / jakość)

### Wersja A — Python (`logging`, dobre praktyki)

- **Moduł:** `logging` (stdlib), jeśli potrzebne są poziomy, rotacja i **timestamp na każdej linii** w pliku.
- **Format czasu:** np. `%(asctime)s` z `datefmt="%Y-%m-%d %H:%M:%S"` — jedna spójna strefa (lokalna lub UTC), **jawnie** opisana w kodzie.
- **Plik obrotowy (opcjonalnie):** `RotatingFileHandler` / `TimedRotatingFileHandler`.
- **Stan w repo:** `insert_from_mt5_html.py` używa głównie **`print`** na stdout i postępu na stderr — pełne timestampy per linia w pliku z BAT wymagałyby **`logging`** w skrypcie (obecnie: banner z BAT + surowy stdout).

### Wersja B — MQL5 / EA (`DailySessionLogger_v2.mq5`)

- **Kanał:** `Print` / `PrintFormat` → Eksperci + `MQL5\Logs`.
- **Czas zdarzenia w treści:** `TimeToString(dt, TIME_DATE|TIME_MINUTES)` tam, gdzie chodzi o czas deala / skanu historii (nie mylić ze znacznikiem czasu samego pliku logu MT5).
- **Alerty:** `Alert` + często `Print` + `SendNotification` dla progów (np. margin / total lot) — ten sam tekst może iść na trzy kanały.

---

## `DailySessionLogger_v2.mq5` — mapa aktywności (prefiksy / obszary)

Komentarz w kodzie (ok. linii 98): *Logi `Print` trafiają do MQL5\Logs (Experts) i są kluczowe diagnostycznie.*

Kolumna **Kod** wskazuje **funkcję** (lub krótki opis miejsca) w pliku `DailySessionLogger_v2.mq5`, gdzie występuje dany `Print` / `PrintFormat` / `Alert` / `SendNotification` (numery linii mogą się przesuwać przy edycjach).

### Start / OnInit

| Prefiks / treść | Rola | Kod |
|-----------------|------|-----|
| `DailySessionLogger_v2 started. login=` | Potwierdzenie startu EA | `OnInit` |
| `OnInit AccountAge: WZNOWIONO okres z pliku .state` / `NOWY okres` | Stan `AccountAge` / `period_uid` | `OnInit` (ścieżka `AccountAge`) |

### Wykrywanie resetu salda / skan historii

| Prefiks | Rola | Kod |
|---------|------|-----|
| `BalanceResetDetect:` | Skan historii, zakres czasu, `HistorySelect`, znaleziony reset | `BalanceResetDetect` |
| `HandleBalanceReset: ENTER` / `EXIT` | Wejście/wyjście obsługi resetu | `HandleBalanceReset` |
| `AccountAgeReport: new life period started` | Nowy okres życia konta po resecie | `HandleBalanceReset` (przed `UpsertAccountAgeRow`) |

### Nagłówki i tworzenie plików CSV

| Prefiks | Rola | Kod |
|---------|------|-----|
| `EnsureHeaderDaily:` | Plik dzienny `g_daily_file` (globalny podsumowujący wg EA) | `EnsureHeaderDaily` |
| `EnsureHeaderDailyPerAccount:` | Plik dzienny per konto | `EnsureHeaderDailyPerAccount` |
| `EnsureHeaderDailyDealsPerAccount:` | Plik deali per konto (nowy plik → reset kursorów) | `EnsureHeaderDailyDealsPerAccount` |
| `EnsureHeaderAccountAge:` | `AccountAgeReport.csv` | `EnsureHeaderAccountAge` |
| `Cannot create global daily summary file` | Błąd utworzenia pliku globalnego podsumowania | `EnsureHeaderDailyGlobal` |
| `Cannot create deals file` | Błąd utworzenia `InpDealsFile` | `EnsureHeaderDeals` |
| `Cannot create thresholds file` | Błąd utworzenia `InpThreshFile` | `EnsureHeaderThresh` |

### `AppendRow` / kolejka przy zablokowanym pliku

| Prefiks | Rola | Kod |
|---------|------|-----|
| `DEBUG AppendRow: file=` (`PrintFormat`) | Diagnostyka przy zapisie | `AppendRow` |
| `AppendRow: OCHRONA DailySessionSummary` | Walidacja 14 kolumn schematu globalnego | `AppendRow` |
| `AppendRow: target locked` / `ALSO failed queue` | Kolejka `.queue` gdy Excel blokuje plik | `AppendRow` |
| `FlushPendingWriteQueueForFile:` | Sukces / błąd opróżnienia kolejki do pliku docelowego | `FlushPendingWriteQueueForFile` |

### Sesja dzienna — `UpsertDailyRow` / koniec sesji

| Prefiks | Rola | Kod |
|---------|------|-----|
| `DEBUG UpsertDailyRow ENTER` / `DEBUG UpsertDailyRow:` / `DONE` (`PrintFormat`) | Ścieżka upsertu wiersza dziennego | `UpsertDailyRow` |
| `DEBUG NotifySessionEnd ENTER` | Wejście w zamknięcie sesji (debug) | `NotifySessionEnd` |
| `AppendDailyFinalRow:` | Zapis końcowego wiersza sesji | `AppendDailyFinalRow` |
| `DEBUG EndSessionFinalize` … | Finalizacja sesji, przed/po `AppendDailyFinalRow` | `EndSessionFinalize` |
| `DEBUG EndSession condition` | Wykrycie końca sesji (`open_cnt==0`) przed `EndSessionFinalize` | `UpdateSessionMetrics` |
| `NotifySessionEnd:` / `Print(msg)` | Podsumowanie sesji; błędy `SendNotification` | `NotifySessionEnd` |

**Alerty przy zamknięciu sesji:** wiele ścieżek z **`Alert(msg); Print(msg); SendNotification(msg);`** w **`NotifySessionEnd`** (progi equity / margin / total lot itd.).

### Deale — `LogDealPerAccount` / `ProcessCloseDeals`

| Prefiks | Rola | Kod |
|---------|------|-----|
| `LogDealPerAccount` (`PrintFormat` / `Print`) | Zapis deala: ticket, czas, symbol, zysk, metryki sesji | `LogDealPerAccount` |
| `WARN: g_session_start_time==0` | Fallback czasu sesji | `LogDealPerAccount` (lub powiązana ścieżka deali) |
| `ProcessCloseDeals:` | Wejście, `HistorySelect`, zysk sesji, podejrzenie „late profit”, retry | `ProcessCloseDeals` |
| `DEBUG ADD pos` / `DEBUG ADD neg` | Diagnostyka agregacji deali | `ProcessCloseDeals` |
| `DEBUG ProcessCloseDeals pre-retry` (`PrintFormat`) | Odtwarzanie deali przed ponowieniem | `ProcessCloseDeals` |

### Account Age — sidecar i CSV

| Prefiks | Rola | Kod |
|---------|------|-----|
| `LoadAccountAgeSidecar:` | Niezgodność UID — czyszczenie pliku `.state` | `LoadAccountAgeSidecar` |
| `SaveAccountAgeSidecar:` | Błąd zapisu sidecar | `SaveAccountAgeSidecar` |
| `HydrateAccountAgeFromCsv:` | Udany odczyt UID / brak wiersza | `HydrateAccountAgeFromCsv` |
| `UpsertAccountAgeRow:` | Pełna ścieżka upsertu (odczyt, naprawa nagłówka, UPDATE/APPEND/WARNING, zapis) | `UpsertAccountAgeRow` |
| `AppendAccountAgeRowFinal:` | Błąd otwarcia pliku | `AppendAccountAgeRowFinal` |
| `AccountAgeReport: appended row` | Dopisanie wiersza raportu wieku konta | `AppendAccountAgeRowFinal` |

### Inne

| Element | Rola | Kod |
|---------|------|-----|
| `LogThreshold(...)` | **Brak `Print`** — tylko zapis wiersza do pliku progów (`AppendRow` na `InpThreshFile`) | `LogThreshold` |
| `Cannot save session id` | Błąd zapisu identyfikatora sesji | `SaveLastSessionId` |

---

## Python — skrypty w `scripts\`

### `scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py`

| Kanał | Zawartość |
|-------|-----------|
| **stdout** | Podsumowania (`Deals:`, `Summary:`), raport QA (`QA deals`, próbki ticketów), komunikaty końcowe (`Dry-run`, ścieżki wyjścia) |
| **stderr** | Postęp skanowania HTML (`tqdm` lub fallback `%`), komunikaty pomocnicze (`tr_scanned` itd.) |
| **Uwaga** | Przy `PYTHONUNBUFFERED=1` i `py ... >> log` stdout trafia do pliku **bez** opóźnienia bufora |

### `scripts/csv_repair_horizontal_summary/repair_daily_session_summary.py`

| Kanał | Zawartość |
|-------|-----------|
| **stdout** | Statystyki naprawy (liczby linii, kolumn), ścieżka zapisu / dry-run |
| **stderr** | Błąd braku pliku wejściowego |

---

## Launchery BAT: `set /p` vs `choice`

- W **`set /p`** unikaj znaku **`*`** w tekście pytania (CMD może rozwinąć wildcard).
- W **`run_insert_PRE.bat`** (Krok B, Krok C) używane jest **`choice /C TN`** — użytkownik wciska **T** lub **N** (Enter **nie** wybiera „Tak”).
- **Gałąź po `choice`:** używać **`if errorlevel 2 goto :etykieta`** (w CMD: `if errorlevel n` = **ERRORLEVEL ≥ n**). **Nie** polegać na `set "X=!ERRORLEVEL!"` zaraz po `choice` — w delayed expansion bywa błędnie; patrz **ID-88** w `docs/CHANGE_LOG.md`.

## Launchery BAT: `run_insert_PRE_last.log` i `run_insert_pytest_last.log`

| Aspekt | Zachowanie |
|--------|------------|
| **Nadpisywanie** | **Tak — przy starcie każdego uruchomienia** pierwsza linia używa `>` i **czyści plik** („ostatni run”). |
| **Znacznik czasu w liniach z BAT** | Prefiks **`YYYY-MM-DD HH-mm-ss`** (`:ts` + PowerShell). |
| **Stdout Pythona** | Bez prefiksu czasu BAT na każdej linii; przed blokiem jest linia `[INFO] --- Python stdout ...`. |
| **stderr Pythona** | Domyślnie **konsola** (postęp), nie scala się do logu — żeby nie ukrywać paska w pliku. |
| **NOPAUSE** | Jeśli ustawione w środowisku — koniec skryptu **bez** `pause` (ostrzeżenie na początku PRE). |

---

## Historia zmian (skrót)

- Znaczniki czasu w BAT, `choice`, polityka `*_last.log`, mapa EA + kolumna **Kod** — `docs/CHANGE_LOG.md` (ID m.in. 85–86, **88** — `choice` + `ERRORLEVEL`, **89** — mapowanie wyjścia → funkcja/plik).
