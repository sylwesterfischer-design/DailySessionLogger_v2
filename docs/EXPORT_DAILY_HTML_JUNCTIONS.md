# EA `ExportDailyHistoryHtml.mq5` — eksport dzienny HTML + junctiony

**Ten dokument nie zmienia schematu** `DailySessionDeals<konto>.csv` ani innych plików CSV EA — opisuje **pomocniczy EA** zapisujący **własny** plik HTML w `Common\Files`.

## Czego to **nie** jest (ważne)

- **To nie jest** kliknięcie *Raport → HTML* z terminala MT5. W MQL5 **nie ma** prostego wywołania „zrób ten sam plik co z menu Historia”. EA **nie odtwarza** szablonu MT5 1:1 (CSS, wielostronicowe raporty, sekcje „Pozycje” itd.).
- **To nie jest** zapis **CSV** — powstaje wyłącznie plik **`.html`** (tabela dealów).

## Czym jest (po co to w ogóle)

- **Automatyczny** plik **HTML** z **HistoryDeal** (te same deale co w historii konta), raz dziennie o zadanej godzinie — **archiwum / podgląd w przeglądarce** bez ręcznego eksportu.
- Dodatkowo układ kolumn jest **zgodny** z parserem `insert_from_mt5_html.py` przy **`--layout deals-default`** — *jeśli* kiedyś użyjesz insertu, masz spójny ticket/czas/profit. **Nie musisz** uruchamiać Pythona ani dotykać CSV, żeby EA miał sens — to tylko **opcja** na później.

Jeśli potrzebujesz **wyłącznie** „oficjalnego” wyglądu raportu z MT5 — zostaje **ręczny** eksport z menu; EA jest **zamiennikiem automatycznym po danych**, nie klonem generatora MT5.

## Przepływ: EA + junction + Python — **bez** drugiego automatu / kopiowania

**Kolejność czasowa:** najpierw **EA** (musi istnieć plik `.html`), **dopiero potem** — gdy chcesz uzupełnić CSV — **Python** `insert_from_mt5_html.py`. Odwrotnie nie ma sensu (skrypt czyta HTML jako wejście).

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
