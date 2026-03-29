# EA `ExportDailyHistoryHtml.mq5` — eksport dzienny HTML + junctiony

> [!CAUTION]
> ### Kolejność kroków — **najpierw HTML, potem Python** (nie odwracaj)
>
> 1. **Terminal MT5 na koncie docelowym** → uruchom **`ExportDailyHistoryHtml.mq5`** i **pobierz / wygeneruj raport HTML** dla **tego samego loginu**, którego ma dotyczyć insert (timer 23:59, przycisk **„Eksport HTML teraz”**, albo `InpRunOnceNow` — patrz niżej). **Bez tego pliku `.html` skrypt insert nie ma wejścia.**
> 2. **Dopiero potem** → `scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py` z `--html` wskazującym **konkretny** wygenerowany plik oraz `--deals-in` na **`DailySessionDeals<LOGIN>.csv`** **tego samego** konta.
>
> **Warunki wstępne (checklista):**
>
> - Masz **fizycznie zapisany** plik `…\ReportHistoryAuto-<LOGIN>_YYYY-MM-DD.html` (nazwa zależy od dnia eksportu i `InpFileNamePrefix` / `InpSubfolder` w EA).
> - **Login w HTML = login w `--konto` / `--deals-in`** — insert jest per konto; nie mieszaj raportu z konta A z CSV konta B.
> - Istnieje docelowy **`DailySessionDeals<LOGIN>.csv`** z **poprawnym nagłówkiem** (insert dopisuje brakujące tickety; nie „wynajduje” pliku deals z niczego).
> - (Opcjonalnie) **Junction** `Common\Files\reports_<LOGIN>` → folder `reports_<LOGIN>` w repo — wtedy HTML widać obok kodu; bez junctionu ścieżka do `--html` może być absolutna pod `Common\Files\...`.
> - **Wiele kopii MT5:** `ExportDailyHistoryHtml.mq5` musisz **wgrać** do `MQL5\Experts\` **tej** kopii terminala, na której jesteś zalogowany na docelowe konto, i **skompilować w MetaEditorze tej kopii** — szczegółowa lista instalacji: `docs/trading_accounts_mt5.md`.

**Ten dokument nie zmienia schematu** `DailySessionDeals<konto>.csv` ani innych plików CSV EA — opisuje **pomocniczy EA** zapisujący **własny** plik HTML w `Common\Files`.

## Czego to **nie** jest (ważne)

- **To nie jest** kliknięcie *Raport → HTML* z terminala MT5. W MQL5 **nie ma** prostego wywołania „zrób ten sam plik co z menu Historia”. EA **nie odtwarza** szablonu MT5 1:1 (CSS, wielostronicowe raporty, sekcje „Pozycje” itd.).
- **To nie jest** zapis **CSV** — powstaje wyłącznie plik **`.html`** (tabela dealów).

## Czym jest (po co to w ogóle)

- **Automatyczny** plik **HTML** z **HistoryDeal** (te same deale co w historii konta), raz dziennie o zadanej godzinie — **archiwum / podgląd w przeglądarce** bez ręcznego eksportu.
- Dodatkowo układ kolumn jest **zgodny** z parserem `insert_from_mt5_html.py` przy **`--layout deals-default`** — *jeśli* kiedyś użyjesz insertu, masz spójny ticket/czas/profit. **Nie musisz** uruchamiać Pythona ani dotykać CSV, żeby EA miał sens — to tylko **opcja** na później.

Jeśli potrzebujesz **wyłącznie** „oficjalnego” wyglądu raportu z MT5 — zostaje **ręczny** eksport z menu; EA jest **zamiennikiem automatycznym po danych**, nie klonem generatora MT5.

## Junctiony w katalogu projektu (`DailySessionLogger_v2`)

W rootzie repo mogą być m.in. **`scripts_<LOGIN>`**, **`reports_<LOGIN>`**, **`data\reports_<LOGIN>`**, **`logs_<LOGIN>_terminal`** — to **dowiązania** do konkretnego profilu `Terminal\<HASH>\…` lub do **`Common\Files`**.  
**AI w Cursorze** ma czytać pliki przez te ścieżki, gdy istnieją w workspace (np. `Read` na `scripts_10827887\*.mq5`, `data\reports_10827887\*.html`, `logs_*_terminal\*.log`) — zgodnie z **§1d.3 / §1d.8 / §1d.9** w `.cursorrules_General` oraz listą w **`docs/JUNCTIONS_INVENTORY.md`**.

## Dwa różne „raporty” w folderach `reports_*` (nie mylić)

| Źródło | Typowa nazwa pliku | Gdzie fizycznie | Uwagi |
|--------|-------------------|-----------------|--------|
| **Auto** `ExportDailyHistoryHtml` | `ReportHistoryAuto-<LOGIN>_YYYY-MM-DD.html` | **`%APPDATA%\MetaQuotes\Terminal\Common\Files\reports_<LOGIN>\`** | Tabela deali z **API** (`HistorySelect`). **Harmonogram 23:59:** od **północy „dziś” (serwer)** do **teraz**. **RunOnce + przycisk:** domyślnie tak samo; od wersji **1.02** możesz ustawić **`InpUseCustomDay=true`** + **`InpDayYmd=YYYY-MM-DD`**, żeby wyciągnąć **pełny wskazany dzień** (00:00–23:59 serwera). |
| **Ręczny** *Historia → zapisz raport HTML* | często `ReportHistory-<LOGIN>.html` (inna konwencja) | Często **`…\Terminal\<HASH>\MQL5\Reports\`** | Pełniejszy / inny szablon MT5; **nie** musi pasować do `--layout deals-default`. |

Junction **`reports_10827887` → `MQL5\Reports`** (jak na Twoim zrzucie) pokazuje **ręczne** eksporty — **nie** zastępuje zapisu do **`Common\Files`** (auto).

## `InpRunOnceNow` i przycisk — **kiedy** eksport, nie **który dzień**

Parametry **„jednorazowy eksport przy starcie”** oraz **„przycisk Eksport HTML teraz”** ustawiają tylko **moment wywołania** (bez czekania do 23:59). **Domyślnie** zakres danych to nadal **od północy bieżącego dnia serwera do „teraz’’** — to **nie** jest wybór daty z kalendarza, dopóki nie włączysz **`InpUseCustomDay`** (v **1.02**, patrz tabela wyżej).

## Dlaczego `ReportHistoryAuto-…html` jest „pusty” (tylko nagłówki)?

Kod `ExportDayHtml(...)` (plik w `scripts_10827887` oraz **`ExportDailyHistoryHtml.mq5`** w korzeniu repo):

1. Wywołuje `HistorySelect(day_start, day_end)` — przy ustawieniach domyślnych **dzień kalendarzowy czasu SERWERA**: od **północy** bieżącego dnia do **chwili eksportu**; przy **`InpUseCustomDay`** — **pełny** dzień z `InpDayYmd`.
2. Do HTML trafiają wyłącznie deale **BUY** i **SELL** (inne typy są pomijane).
3. Jeśli w tym przedziale **nie ma** takich deali → plik nadal powstaje, ale **0 wierszy** — w przeglądarce widać tylko `<th>…</th>` (jak na Twoim zrzucie ~1 KB).

**Co zrobić diagnostycznie:** na terminalu **11323AE…** (konto 10827887) otwórz **Toolbox → Eksperci** i szukaj linii:

`ExportDailyHistoryHtml: OK nDeals=0 file=…` **albo** `nDeals=` **> 0**.

Jeśli **0** — typowe przyczyny: **inna data serwera** niż dzień transakcji (wszystko „wczoraj” po czasie brokera), brak zamkniętych deali BUY/SELL dziś, lub historia konta nie załadowana (*Historia konta* → prawy klik → pełna historia, jeśli broker wymaga).

## Ikona „jak EA” przy pliku w `Scripts`

`ExportDailyHistoryHtml*.mq5` używa **`OnInit` / `OnTimer` / `OnChartEvent`** (przycisk na wykresie) — to **model działania jak Expert Advisor**, nie klasyczny skrypt z jednym **`OnStart()`**. Stąd w Nawigatorze **ta sama stylizacja ikony** co przy EA jest **normalna**. Sam fakt folderu `MQL5\Scripts` to **Twoja** organizacja plików; przy problemach z timerem rozważ **Experts** + włączony **Algo Trading**.

## Workflow aktualny (uzgodniony): **ręczny HTML → Python → pliki `*_pyTEST.csv`**

1. **Ty:** zapisujesz raport HTML z MT5 (*Historia konta* → raport HTML) do folderu widocznego w repo — np. junction **`reports_10827887`** → `MQL5\Reports`.
2. **Python:** generuje **testowe kopie CSV** (nie produkcyjne), żeby porównać wynik per `session_id`.
3. **Dopiero po weryfikacji** decydujesz, co przenieść do produkcyjnych CSV.

Przykład dla konta `10827887` (PowerShell, z korzenia repo):

```powershell
py scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py `
  --layout deals-default `
  --html "reports_10827887\ReportHistory-10827887.html" `
  --konto 10827887 `
  --summary-in "$env:APPDATA\MetaQuotes\Terminal\Common\Files\DailySessionSummary.csv" `
  --only-date 2026-03-18 `
  --deals-in "$env:APPDATA\MetaQuotes\Terminal\Common\Files\DailySessionDeals10827887.csv" `
  --qa-report `
  --test-outputs
```

- W tym trybie skrypt zapisuje:
  - `DailySessionDeals10827887_pyTEST.csv`
  - `DailySessionSummary_pyTEST.csv`
  obok plików wejściowych w `Common\Files`.
- W trybie `--test-outputs` pliki `*_pyTEST.csv` zawierają tylko wiersze wynikowe z HTML dla wybranego dnia (`--only-date`) — bez pełnej kopii produkcyjnego CSV.
- **`--only-date`** — opcjonalnie: z dużego HTML (wiele dni) bierze tylko deale z jednego dnia (YYYY-MM-DD).
- **`--konto`** — wymagane: login wpisywany do kolumny `konto` w wygenerowanych wierszach.
- **`--qa-report`** — raport jakości porównania `HTML vs istniejący deals CSV` dla dnia (`common / html_only / csv_only` + sample ticketów).

- Jeśli tabela w HTML jest **po polsku** / sekcja **„Pozycje”** — użyj **`--layout positions-pl`** (`docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md`): mapowanie kolumn + **rekonstrukcja sesji (flat)** z czasu otwarcia/zamknięcia oraz checklista QA względem `ReportHistory-<LOGIN>.html`.
- **`deals-default`** pasuje do **angielskiego** układu kolumn zbliżonego do auto-eksportu (Time, Deal, Symbol, Type, Volume, Price, …) — **bez** czasu otwarcia w osobnym poliu → tylko sesje syntetyczne (`--session-mode`).

Wariant diagnostyczny bez zapisu plików: dodaj **`--dry-run`**.

### Skrót: `.bat` z katalogu głównego (tylko konto + data)

Jeśli nie chcesz składać całej komendy ręcznie, użyj:

```powershell
run_insert_pytest.bat 10827887 2026-03-18
```

Opcjonalnie inny layout (tylko gdy parsowanie wyjdzie puste lub złe — zwykle **nie trzeba**):

```powershell
run_insert_pytest.bat 11693817 2026-03-22 positions-pl
```

**Co to `layout`:** mapowanie kolumn HTML → parser. Dla **raportu z menu MT5** (*Historia → HTML*, `ReportHistory-*.html`) używamy **`positions-pl`** — stałe indeksy kolumn opisane w **`docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md`**. `run_insert_pytest.bat` ma domyślnie **`positions-pl`**. **`deals-default`** tylko dla auto-HTML z `ExportDailyHistoryHtml.mq5` (inna tabela), np. `run_insert_pytest.bat KONTO DATA deals-default`.

Skrypt `.bat` sam:
- buduje ścieżki po konwencji (`reports_<KONTO>\ReportHistory-<KONTO>.html`, `DailySessionDeals<KONTO>.csv`, `DailySessionSummary.csv`),
- waliduje istnienie folderu `reports_<KONTO>` i plików wejściowych CSV,
- waliduje, że istnieje HTML dla konta (nazwa główna lub fallback `ReportHistory*<KONTO>*.html`),
- uruchamia Pythona z `--only-date`, `--qa-report`, `--test-outputs`,
- zwraca czytelny błąd jeśli brakuje lokalizacji albo plik nie pasuje do konwencji nazewnictwa.

## Przepływ: EA + junction + Python — **bez** drugiego automatu / kopiowania

**Kolejność czasowa** (powtórzenie — pełna checklista **na samej górze** dokumentu w bloku CAUTION): najpierw **EA** (musi istnieć plik `.html`), **dopiero potem** — gdy chcesz uzupełnić CSV — **Python** `insert_from_mt5_html.py`. Odwrotnie nie ma sensu (skrypt czyta HTML jako wejście).

1. **`ExportDailyHistoryHtml.mq5`** robi tylko **zapis HTML** o zadanej godzinie — **nie** robi deduplikacji względem CSV. Deduplikacja jest **wyłącznie w** `scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py`, gdy **Ty** uruchomisz skrypt (np. z `--dry-run`). Ten plik `.md` to **dokumentacja** (junction, przykłady).
2. **EA** `ExportDailyHistoryHtml.mq5` zapisuje plik **bezpośrednio** do  
   `Common\Files\<InpSubfolder>\*.html`.  
   Jeśli zrobiłeś **junction** `Common\Files\reports_10828174` → folder w repo `reports_10828174`, to **ten sam zapis** jest od razu widoczny w repo — **nie trzeba** osobnego skryptu kopiującego.
3. **Wykres:** EA może wisieć na **dowolnym** symbolu/TF (**BTCUSD H1** jest OK). Ważne: **konto** terminala = konto, dla którego ustawiłeś `InpSubfolder` (np. `reports_10828174`). Sam symbol **nie** filtruje historii — eksportuje **wszystkie** deale konta w zadanym dniu.
4. **Północ vs 23:59:** domyślnie EA odpala o **23:59** czasu **serwera**. Jeśli chcesz **00:00**, zmień `InpExportHour` / `InpExportMinute` — pamiętaj, że eksportuje zakres **od północy bieżącego dnia serwera do „teraz”** (więc o 00:00 pierwszego ticka nowego dnia dzień „w pliku” to już nowa data — dostosuj oczekiwania).
5. **Python:** ścieżka skryptu w repo to  
   `scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py`  
   (nie `tools/...`). W `--html` podajesz **konkretny plik** (np. `reports_10828174\ReportHistoryAuto-10828174_2026-03-24.html`) albo ścieżkę absolutną; **`--deals-in`** = istniejący `DailySessionDeals10828174.csv` (zwykle w `Common\Files`).

## Co robi EA

- O **ustawionej godzinie czasu serwera** (domyślnie **23:59**) raz dziennie zapisuje HTML z **historii dealów** od **północy serwera** do **chwili eksportu**.
- Format tabeli jest zgodny z oczekiwaniami `insert_from_mt5_html.py` przy **`--layout deals-default`** (kolejność kolumn jak w kodzie Python).
- Plik: `Common\Files\<InpSubfolder>\<InpFileNamePrefix>-<LOGIN>_YYYY-MM-DD.html`  
  Przykład: `...\Common\Files\reports_10827887\ReportHistoryAuto-10827887_2026-03-23.html`

## Dlaczego junction (a nie ścieżka do `Experts\Advisors\...`)

MT5 **nie pozwala** EA zapisywać poza katalogami danych terminala (`MQL5\Files`, **`Common\Files`**).  
Folder **`...\DailySessionLogger_v2\reports_10827887`** musi być **tym samym katalogiem** co podfolder w `Common\Files` — robisz to **junctionem** (lub symlinkiem).

## Mapowanie: konto → junction (szablon)

| Login MT5 | Podfolder w `Common\Files` (`InpSubfolder`) | Folder docelowy w repo (przykład) |
|-----------|---------------------------------------------|-----------------------------------|
| 10827887  | `reports_10827887` | `...\DailySessionLogger_v2\reports_10827887` |
| *następne konto* | `reports_<LOGIN>` | `...\DailySessionLogger_v2\reports_<LOGIN>` |

**Na jednym wykresie / koncie** ustawiasz `InpSubfolder` **zgodnie z loginem** tego konta. Drugie konto = druga instancja EA na wykresie tego konta albo inny profil terminala.

### Utworzenie junction (PowerShell **jako administrator**)

Dostosuj ścieżki (hash terminala u Ciebie: `49C33A939697AEF354FFC02653AB58DE`).

```powershell
$commonFiles = "$env:APPDATA\MetaQuotes\Terminal\Common\Files"
$target      = "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\reports_10827887"

# Jeśli folder docelowy nie istnieje — utwórz
New-Item -ItemType Directory -Force -Path $target | Out-Null

# Junction: Common\Files\reports_10827887 → repo
cmd /c mklink /J "$commonFiles\reports_10827887" "$target"
```

Jeśli **`reports_10827887`** już istnieje w `Common\Files` jako zwykły folder — usuń go lub zmień nazwę **przed** `mklink`.

## Ustawienia EA (skrót)

| Input | Typowy wpis |
|-------|-------------|
| `InpExportHour` / `InpExportMinute` | `23` / `59` |
| `InpExportSecondMax` | `59` (pierwszy tick timera w tej minucie z sekundą ≤ 59) |
| `InpSubfolder` | `reports_10827887` |
| `InpRunOnceNow` | `true` na chwilę — test zapisu przy starcie EA; potem `false` |
| `InpShowExportButton` | `true` — na wykresie (lewy górny róg) przycisk **„Eksport HTML teraz”** = natychmiastowy zapis (pokazowy, bez czekania do 23:59); `false` — bez przycisku |

## Python (insert)

```powershell
py scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py `
  --layout deals-default `
  --html "reports_10827887\ReportHistoryAuto-10827887_2026-03-23.html" `
  --konto 10827887 `
  --deals-in "$env:APPDATA\MetaQuotes\Terminal\Common\Files\DailySessionDeals10827887.csv" `
  --dry-run
```

## Przykład deduplikacji (do porównania w głowie / Excelu)

**Cel skryptu insert:** nie dublować wierszy, które **już są** w `DailySessionDeals<konto>.csv`, tylko **dopisać brakujące** deale widoczne w HTML.

Załóżmy kolumnę **`deal_ticket`**:

| Źródło | Zestaw ticketów (uproszczenie) |
|--------|--------------------------------|
| **CSV** (już zapisany przez EA logger) | `1001`, `1002`, `1003` |
| **HTML** (z eksportu / z `ExportDailyHistoryHtml`) | `1001`, `1002`, `1003`, `1004`, `1005` |

- **Wspólne** (`1001`–`1003`) → skrypt **pomija** (uznaje, że już są w CSV).
- **Tylko w HTML** (`1004`, `1005`) → trafiają do listy **„do dopisania”** w pliku `*_INSERT.csv` (przy realnym uruchomieniu bez `--dry-run`).

**Nie** chodzi tu o „który raport jest ładniejszy”, tylko o **zbiór ticketów**: dopisujemy tickety **występujące w HTML, a nieobecne w CSV** (różnica zbiorów).

Jeśli **nie uruchamiasz** insertu — ten przykład możesz zignorować; sam plik HTML z EA i tak jest **pełną listą dealów** z dnia w tabeli.

## Zapis tylko do `Common\Files` — czy wtedy EA = raport MT5 **1:1**?

**Nie.** Miejsce zapisu (**`%APPDATA%\MetaQuotes\Terminal\Common\Files\...`**) nie zmienia faktu, że MQL5 **nie wywołuje** wbudowanego generatora *Raport → HTML*. EA **zawsze** składa HTML z **`HistoryDeal`** po swojemu (prosta tabela). To **te same dane dealowe** co w terminalu (dla danego zakresu czasu), ale **nie** ten sam plik/szablon co z menu.

## Junction: cały `Common\Files` vs tylko `reports_<LOGIN>`

**Nie rób junctionu na cały katalog `Common\Files`.**

Powód: tam leżą m.in. **`DailySessionSummary.csv`**, **`DailySessionDeals<konto>.csv`**, pliki stanu EA, inne wspólne pliki MT5. Gdybyś podpiął **cały** `Common\Files` pod jeden folder w repo (albo pod `reports_*`), **wszystkie** te pliki by się „przeniosły” logicznie w jedno miejsce — **rozjedzie się** konfiguracja terminala i inne EA.

**Bezpieczny wzorzec (ten z dokumentu):**

- **Jeden junction na konto** tylko dla podfolderu raportów:  
  `Common\Files\reports_10827887` → `...\DailySessionLogger_v2\reports_10827887`
- To **nie zastępuje** innych junctionów, które masz do **logów** / **`data\`** — to **inna rola** (CSV vs raporty HTML).

**Czy możesz skasować istniejące junctiony `reports_10828174` itd.?**

- **Tak**, jeśli **świadomie** rezygnujesz z tego, żeby te pliki HTML były widoczne w repo przez ten link — wtedy raporty zostają tylko „fizycznie” pod prawdziwą ścieżką `Common\Files\...` (bez podglądu w folderze projektu).
- **Nie** zamieniaj wielu `reports_*` na **jeden** junction całego `Common\Files` — to zła zamiana (patrz wyżej).

**Repo + Cursor:** wygodnie jest mieć **junction per konto** tylko na `reports_<LOGIN>`, żeby w workspace od razu widać było `ReportHistoryAuto-*.html` obok kodu.

## Uwagi

- To **nie** jest pikselowy klon raportu z menu MT5 — tylko **tabela dealów** pod parser.
- **Tester strategii** — zachowanie historii może być inne niż na koncie live/demo.
- Kolumna **Balance** w HTML to placeholder (`0`); insert korzysta głównie z ticket / czas / profit.
