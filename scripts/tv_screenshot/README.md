# Zrzuty wykresu (Playwright)

## Jednorazowa instalacja (z rootu `DailySessionLogger_v2`)

```powershell
python -m venv .venv
.\.venv\Scripts\pip install -r scripts\tv_screenshot\requirements.txt
.\.venv\Scripts\playwright install chromium
```

`python -m venv .venv` **nie drukuje nic**, jeśli się udało — sprawdź folder `.venv\`.

**Windows + czas polski w nazwach PNG:** moduł `zoneinfo` wymaga bazy stref (`tzdata`) — jest w `requirements.txt`. Zamknięcie okna PowerShell **nie usuwa** pakietów z `.venv`; `pip install -r …` możesz puścić w **dowolnym** nowym oknie po `cd` do tego samego rootu repo. Upgrade `pip` (`python -m pip install --upgrade pip`) jest **opcjonalny**, nie jest potrzebny do działania zrzutów.

## Checklist: zrzut z wskaźnikami (layout jak w Chrome)

Gdy na PNG widać **ten sam** układ co po zalogowaniu w zwykłej przeglądarce (bez „Trybu podglądu”, bez czerwonych `!` przy Pine):

1. Istnieje **`scripts/tv_screenshot/tv_storage_state.json`** (po `save_tv_storage_state.py` + Enter); w `capture_schedule.json` jest **`storage_state`** na ten plik.
2. Przy zapisie sesji w Chromium **otwarty był dokładnie ten layout** (`/chart/…`), cookies zaakceptowane, wskaźniki bez błędów **przed** Enter.
3. **Harmonogram i zapis sesji** używają wspólnych argumentów startu Chromium (`CHROMIUM_LAUNCH_ARGS` w kodzie — m.in. `AutomationControlled` wyłączone); po aktualizacji repo warto zrobić **jeden** nowy zrzut.
4. Gdy headless nadal ucina Pine: **`"headed": true`** w `capture_schedule.json` albo diagnostyka: `diagnose_tv_session.py` / `diagnose_tv_session.py --headed`.

## Przykład

```powershell
cd ...\DailySessionLogger_v2
.\.venv\Scripts\python scripts\tv_screenshot\screenshot_tv.py --url "https://pl.tradingview.com/chart/PoqvuZcl/?interval=60"
```

Wynik domyślnie: `docs/tv_playwright_capture.png`.

- `**--headed**` — okno przeglądarki (logowanie na TV, problemy z CAPTCHA).
- `**--wait-ms 12000**` — dłuższe czekanie na załadowanie wykresu.

## Gdzie trafiają pliki

| Tryb | Folder / plik |
|------|----------------|
| Jednorazowy `screenshot_tv.py` (domyślnie) | `docs/tv_playwright_capture.png` |
| Harmonogram `scheduled_screenshots.py` | `docs/tv_scheduled/` — np. `M1_20260329_172702_chart.png` (`{label}_{czas_PL_Europe/Warsaw}_{filename_suffix}.png`; logi w pliku nadal UTC) |
| **Log harmonogramu zrzutów** | `docs/tv_scheduled/tv_capture.log` (`log_file` w `capture_schedule.json`) — przy `pythonw` / zadaniu Windows to główny ślad diagnostyczny |
| **Log zapisu sesji TV** | `scripts/tv_screenshot/tv_save_session.log` — tylko dla `save_tv_storage_state.py` (osobno od `tv_capture.log`) |

**Pełna tabela i wyjaśnienia:** [`docs/TV_SCREENSHOT_LOGGING.md`](../../docs/TV_SCREENSHOT_LOGGING.md).

### Log modeli (OCR) → Excel po każdym zrzucie

Opcjonalnie: blok **`models_log`** w `capture_schedule.json` — po udanym PNG dopisuje wiersz do `trading_models.xlsx` (arkusz `{M1|S15|M5|…}_models_log`), zgodnie ze schematem jak w `schema_models.xlsx`. Wymaga **Tesseract OCR** i `pip install …` (openpyxl, pytesseract, Pillow). Instrukcja, junction, przycinanie obrazu: **[`docs/MODELS_LOG_EXCEL.md`](../../docs/MODELS_LOG_EXCEL.md)**.

Playwright pobiera Chromium do `%LOCALAPPDATA%\ms-playwright\` (poza repo).

### Dlaczego folder z PNG jest pusty, a „nic się nie dzieje”?

- `**pythonw.exe`** (harmonogram) **nie pokazuje** błędów w oknie — stdout/stderr idą w próżnię. Diagnoza: otwórz `**docs/tv_scheduled/tv_capture.log`**.
- Zobaczysz tam m.in.: start procesu (PID, ścieżka `python.exe`), katalog wyjścia PNG, każdy **CAPTURE start / ok / FAIL** z pełną ścieżką pliku i rozmiarem, albo traceback przy awarii Playwright/Chromium.
- Jeśli **nie ma nawet pliku logu** — zadanie harmonogramu prawdopodobnie **nie uruchomiło** skryptu (np. nie było ponownego logowania od instalacji). Uruchom ręcznie: `Start-ScheduledTask -TaskName 'DailySessionLogger_TV_Screenshots'` albo jednorazowo `.\.venv\Scripts\python scripts\tv_screenshot\scheduled_screenshots.py` — wtedy log i tak trafi do `tv_capture.log`.
- W **Harmonogramie zadań** (`taskschd.msc`) → `DailySessionLogger_TV_Screenshots` → **Historia** włącz, jeśli chcesz widzieć start/koniec zadania po stronie Windows (osobno od treści `tv_capture.log`).

## Domyślny wykres (BTCUSD, feed Vantage)

W `capture_schedule.json` / `capture_schedule.example.json` ustawiony jest **zapisany layout** z Twojego konta: [chart PoqvuZcl](https://pl.tradingview.com/chart/PoqvuZcl/) — ten sam symbol i broker (np. Vantage) co w przeglądarce; zmiana interwału idzie przez `?interval={tv_interval}` w harmonogramie. Nie trzeba podawać osobno symbolu w URL, jeśli jest już zapisany w layoucie.

## Wskaźniki na zrzucie (np. ziksfx Structure, Multi Length BoS+ChoCh)

Linki typu [ziksfx Structure - Lite](https://pl.tradingview.com/v/Wlu2LO31/) lub [Multi Length Market Structure](https://pl.tradingview.com/v/Bayq7qtD/) prowadzą do **strony skryptu** (`/v/...`), a nie do **Twojego wykresu** z już dodanymi wskaźnikami.

Żeby na PNG były oba wskaźniki:

1. W TradingView **dodaj wskaźniki** na wykres (jak zwykle z menu).
2. **Zapisz layout** (lub użyj istniejącego).
3. Skopiuj **link do wykresu**: menu wykresu → **Udostępnij** / **Copy link** — URL postaci `https://www.tradingview.com/chart/xxxxxxxx/` lub z parametrami symbolu.
4. Wklej ten URL jako `**chart_url_template`** w `capture_schedule.json`. Jeśli link nie zawiera `interval={tv_interval}`, możesz dopisać parametry ręcznie albo użyć szablonu z przykładu (ten sam wykres, zmiana TF przez `interval` w URL — działa, gdy TV tak zapisuje w linku).

**ziksfx Structure - Lite** jest [chronionym skryptem](https://pl.tradingview.com/v/Wlu2LO31/) — nie da się „włączyć go” z poziomu Playwright przez API; musi być **zapisany na Twoim koncie** na wykresie.

**Multi Length (BoS + ChoCh)** jest [open-source na TV](https://pl.tradingview.com/v/Bayq7qtD/) — dodajesz z biblioteki; kod w Pine masz w edytorze TV, **nie trzeba** go duplikować w tym repo pod zrzuty.

### Tryb podglądu, baner cookies, czerwone wykrzykniki przy wskaźnikach

Jeśli na PNG widzisz **„Tryb podglądu”**, **baner cookies** albo **czerwone wykrzykniki** przy wskaźnikach (jak w zrzucie z przeglądarki), a w normalnym Chrome ten sam [link do layoutu](https://pl.tradingview.com/chart/PoqvuZcl/) wygląda dobrze — przyczyna jest prawie zawsze ta sama:

1. **Brak sesji TV w Playwright** — bez pliku `**storage_state`** Chromium jest „gościem”. Wtedy TV często pokazuje **podgląd** i wskaźniki mogą **nie zdążyć się zainicjalizować** tak jak w zwykłej przeglądarce po zalogowaniu (dotyczy też skryptów darmowych — problem to **sesja**, nie cena skryptu).
2. **Rozwiązanie:** jednorazowo zapisz sesję (`save_tv_storage_state.py`, kroki poniżej). W `capture_schedule.json` jest już ustawione `**storage_state`** na `scripts/tv_screenshot/tv_storage_state.json` — musi **istnieć** ten plik (po zapisie sesji).
3. Skrypt stara się kliknąć **Akceptuję / Accept** po załadowaniu strony (baner), ale pełna zgodność z TV bywa zmienna — sesja zalogowanego użytkownika jest i tak **konieczna** do Twojego layoutu ze wskaźnikami.
4. Możesz zwiększyć `**wait_ms`** (np. 15000), jeśli wskaźniki ładują się wolno po starcie.

## Zalogowane konto (sesja)

**Nie mam dostępu do Twoich ciasteczek z Chrome ani do Twojego dysku zdalnie.** Sesji TV dla Playwrighta **nie da się** „podpiąć” z przeglądarki automatycznie — musisz **raz** zalogować się w oknie, które otwiera `save_tv_storage_state.py`; wtedy powstanie plik `**tv_storage_state.json`** tylko u Ciebie lokalnie.

W `**capture_schedule.json**` jest już wpis: `**"storage_state": "scripts/tv_screenshot/tv_storage_state.json"**` — dopóki ten plik **nie istnieje** (nie zrobiłeś kroków poniżej), harmonogram zapisze w logu ostrzeżenie i zrzuty pójdą bez sesji.

### Krok po kroku: zapis sesji TV (`tv_storage_state.json`)

**Log tej procedury** (start, `goto`, Enter, zapis lub błąd): `scripts/tv_screenshot/tv_save_session.log` — osobno od logu harmonogramu zrzutów (`docs/tv_scheduled/tv_capture.log`).

#### PowerShell: `cd` do rootu i uruchomienie `save_tv_storage_state.py`

Musisz być w katalogu, w którym jest folder **`.venv`**. Samą ścieżkę folderu **wklejona bez** polecenia `cd` PowerShell traktuje jak komendę — stąd błąd „not recognized”.

**Dwie linie (wykonaj po kolei):**

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
```

Sprawdź **prompt**: na końcu powinno być `...\DailySessionLogger_v2>`.

```powershell
.\.venv\Scripts\python scripts\tv_screenshot\save_tv_storage_state.py
```

**Jedna linia** (to samo; ścieżka w **cudzysłowie** jest bezpieczna także przy spacjach w nazwach):

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"; .\.venv\Scripts\python scripts\tv_screenshot\save_tv_storage_state.py
```

Jeśli Twój projekt leży pod **innym** `Terminal\<HASH>\`, podstaw własną ścieżkę do `DailySessionLogger_v2`.

1. Po uruchomieniu powyższego: otworzy się **osobne okno przeglądarki** — to jest **Chromium od Playwrighta** (folder `ms-playwright`), **nie** zainstalowany u Ciebie **Google Chrome** i **nie** Twój profil z Chrome. **Wygląda niemal jak Chrome** (wspólny silnik), stąd łatwe pomylenie — ale logowanie robisz właśnie w tym oknie; ono zapisze `tv_storage_state.json`.
2. W tym oknie:
   - Wejdź na logowanie TradingView (np. z `tradingview.com` → **Zaloguj się**).
   - Zaloguj się **tym samym kontem**, na którym masz zapisany layout wykresu.
3. W **tej samej karcie** otwórz swój wykres, np. [https://pl.tradingview.com/chart/PoqvuZcl/](https://pl.tradingview.com/chart/PoqvuZcl/).
4. Baner cookies — **zaakceptuj** w razie potrzeby.
5. Poczekaj, aż wykres i wskaźniki załadują się **bez czerwonych wykrzykników**.
6. W PowerShellu naciśnij **Enter** — powstanie `scripts/tv_screenshot/tv_storage_state.json` (w `.gitignore`, nie commituj). Skrypt **sam zamyka** okno przeglądarki po zapisie — to nie jest wylogowanie przez TV.

Potem uruchom ponownie `scheduled_screenshots.py` lub zadanie harmonogramu — Playwright wczyta tę sesję.

Pojedynczy test zrzutu z sesją:

```powershell
.\.venv\Scripts\python scripts\tv_screenshot\screenshot_tv.py --url "https://pl.tradingview.com/chart/PoqvuZcl/?interval=60" --storage-state scripts/tv_screenshot/tv_storage_state.json
```

**Brak oficjalnego API TV** — to zwykła przeglądarka z cookies zapisanymi w JSON; 2FA może wymagać ponownego zapisu stanu po wygaśnięciu sesji.

### „Continue with Google” — puste okno (`about:blank`), „Google Chrome for Testing”

W oknie Playwrighta **logowanie przez Google** często **nie dochodzi do końca**: drugie okno zostaje puste albo Google ogranicza OAuth w przeglądarce sterowanej automatycznie. To **normalne ograniczenie**, nie błąd samego skryptu.

**Co zrobić:** na stronie logowania TradingView wybierz **e-mail i hasło** (to samo konto co przy Google — konto TV jest jedno). Jeśli hasła nie ustawiałeś, w ustawieniach konta TV możesz dodać logowanie hasłem.

**Żółty pasek** „Debugger został wstrzymany…” — w DevTools kliknij **wznów** (▶) lub **F8**, albo **zamknij** panel DevTools; wstrzymany debugger blokuje JS i OAuth.

### CAPTCHA — komunikat „Potwierdź, że nie jesteś robotem”, ale brak pola

W **bundled Chromium** z Playwrighta widget reCAPTCHA często **nie ładuje się** (antybot). Spróbuj zapisać sesję przez **zainstalowany Google Chrome**:

```powershell
cd "C:\ścieżka\do\DailySessionLogger_v2"
.\.venv\Scripts\python scripts\tv_screenshot\save_tv_storage_state.py --chrome
```

(`--chrome` = kanał `channel="chrome"` — to nie jest import profilu Chrome, tylko ta sama przeglądarka co na pulpicie, co zwykle poprawia CAPTCHA.)

### Czy musisz przez Google? Drugi profil i powiązanie z Google

**Nie musisz** — to samo konto TV możesz logować **emailem i hasłem** (wygodniejsze przy automatyzacji niż OAuth Google w oknie Playwrighta).

- **Powiązanie z Google:** w TradingView: *Settings* → *Account* → sposoby logowania — możesz **połączyć konto Google** z istniejącym kontem TV (albo odwrotnie, zależnie od tego, jak konto było założone). To **jedno konto TV** z dodatkową metodą logowania, a nie osobny „profil” jak w Chrome.
- **Drugi „profil” / drugi układ:** jeśli chodzi o **drugiego użytkownika TV** (inny zestaw zapisów wykresów), to zwykle potrzebujesz **drugiego konta** (inny adres e-mail). Drugi layout na tym samym koncie to raczej **zapis wykresu / layout** w TV, a nie osobny profil logowania.

**Log:** `scripts/tv_screenshot/tv_save_session.log` — zapisuje m.in. otwarcie nowej karty/popupu (`url=...`), ostrzeżenia z konsoli strony.

**Czemu nie „ciasteczka z Chrome”?** Skrypt **nie** importuje profilu Chrome/Edge. Jest **osobny Chromium**; jedyna sesja dla zrzutów to `**tv_storage_state.json`** wygenerowany powyżej — dopóki go nie utworzysz, automat nie jest zalogowany na TV.

**Czy jak laptop jest wyłączony, nie będzie printscreenów?** Tak — **nowe PNG powstają tylko wtedy**, gdzie działa proces Pythona (`scheduled_screenshots.py` lub ręczny zrzut). Wyłączony komputer = brak uruchomionego harmonogramu. TradingView w chmurze działa dalej, ale **Twój automat lokalny** go nie odpytuje. Żeby zrzuty szły bez Twojego PC, musiałbyś uruchomić ten sam setup (np. VPS) z tym samym `capture_schedule.json` i ważnym `tv_storage_state.json` (lub ponowne logowanie tam).

### „Tryb podglądu”, czerwone `!` przy wskaźnikach (Pine)

To **nie musi** oznaczać złego hasła — TradingView często **uciąża funkcje** (podgląd, skrypty zaproszeniowe), gdy wykryje **automatyzację** (`navigator.webdriver`, **headless**). W zwykłym Chrome na tym samym koncie wskaźniki działają, a w zrzucie nie.

- **Harmonogram** używa tych samych argumentów startu Chromium co `save_tv_storage_state` (`--disable-blink-features=AutomationControlled`). Po aktualizacji repo zrób **jeden** nowy zrzut i porównaj PNG.
- Jeśli nadal źle: w `capture_schedule.json` ustaw **`"headed": true`** (okno widoczne) — często to przywraca pełną sesję; na serwerze bez pulpitu bywa potrzebny wirtualny display.
- Skrypt `diagnose_tv_session.py` pokazuje m.in. **`user_agent_contains_headless_chrome`** — przy domyślnym **headless** UA zawiera `HeadlessChrome`, co TV może traktować jak ograniczoną sesję (nawet gdy `navigator.webdriver` jest `false`).
- **Diagnostyka** (JSON na stdout):

```powershell
.\.venv\Scripts\python scripts\tv_screenshot\diagnose_tv_session.py
.\.venv\Scripts\python scripts\tv_screenshot\diagnose_tv_session.py --headed
```

## Harmonogram (M1 co 5 min, M2 co 4 min, M3 co 6 min, S15 co 5 min, M5, M10, M15, H1, H4, D1)

1. Skopiuj `capture_schedule.example.json` → `**capture_schedule.json`** (obok skryptów); domyślnie jest layout [PoqvuZcl](https://pl.tradingview.com/chart/PoqvuZcl/) — zmień `**chart_url_template**`, jeśli używasz innego zapisu wykresu.
2. Uruchom z rootu repo:

```powershell
.\.venv\Scripts\python scripts\tv_screenshot\scheduled_screenshots.py
```

- Pliki w **jednym** folderze (`output_dir`): `**{M1|M2|M3|…}_{YYYYMMDD_HHMMSS}_{filename_suffix}.png`** — znacznik czasu w nazwie to **czas polski** (`Europe/Warsaw`, CET/CEST), np. `M1_20260329_172702_chart.png`. Sufiks ustawiasz w JSON: `**filename_suffix**` (pusty `""` = stary wzorzec bez trzeciego członu: `M1_20260329_172702.png`).
- **D1** w TV używa w URL wartości `**1D`** (`tv_interval`).
- **S15** — wykres **15 sekund** w TV: `tv_interval` **`15S`**, zrzut co **300 s** (jak M5).
- Wszystkie joby w domyślnym JSON używają `**align: interval**` (co `period_seconds` od poprzedniego zrzutu danego labela).
- Jedna instancja **Chromium** na cały czas (oszczędność RAM vs osobne procesy).

**W tle (Windows) — ręcznie (jednorazowo):**

```powershell
Start-Process -FilePath ".\.venv\Scripts\python.exe" -ArgumentList "scripts\tv_screenshot\scheduled_screenshots.py" -WindowStyle Hidden
```

### Automatycznie po starcie Windows 11 (bez pamiętania)

To **nie** jest usługa Windows w sensie `services.msc`, tylko **Zadanie harmonogramu** (Task Scheduler): przy **logowaniu do Windows** (Twoje konto użytkownika) uruchamia się `pythonw.exe` (bez okna) z `scheduled_screenshots.py`.

**Nie musisz mieć uruchomionego MetaTradera ani „konta master 814”.** Skrypt to **Python + Playwright** na dysku; nie zależy od loginu MT5. Ważne jest tylko: jesteś zalogowany w Windows, działa zadanie harmonogramu i ścieżka do repo (`.venv`, skrypt) jest poprawna.

1. **Najpewniej (bez Execution Policy i bez `powershell` w PATH):** z rootu repo uruchom plik `**install_scheduled_task.cmd`** — możesz **dwukliknąć** go w Eksploratorze (`…\scripts\tv_screenshot\install_scheduled_task.cmd`) albo w terminalu:

```text
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
scripts\tv_screenshot\install_scheduled_task.cmd
```

   Odinstalowanie: `scripts\tv_screenshot\install_scheduled_task.cmd -Remove`

2. **PowerShell:** jeśli wolisz `.ps1`, najpierw w **tej samej sesji** ustaw politykę na proces (bez zmiany systemu):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
.\scripts\tv_screenshot\install_scheduled_task.ps1
```

   Komenda `powershell -File …` często **nie działa**, gdy w PATH nie ma `powershell.exe` (np. tylko `pwsh`). Użyj wtedy **pełnej ścieżki**:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\scripts\tv_screenshot\install_scheduled_task.ps1"
```

3. Opcjonalnie od razu: `Start-ScheduledTask -TaskName 'DailySessionLogger_TV_Screenshots'` — albo wyloguj się i zaloguj.

**Zatrzymanie:** Menedżer zadań → znajdź `pythonw.exe` z ścieżki `.venv\Scripts\` dla tego repo, **Zakończ zadanie** — albo `Stop-ScheduledTask -TaskName 'DailySessionLogger_TV_Screenshots'` (zadanie nadal istnieje, przy następnym logowaniu wystartuje znowu).

**Wyłączenie na stałe:** `scripts\tv_screenshot\install_scheduled_task.cmd -Remove` (albo `.ps1 -Remove` po `Set-ExecutionPolicy -Scope Process …` jak wyżej).

**Uwagi:** działa po **logowaniu** (nie w trybie „bez logowania” przed loginem). Sen / hibernacja: proces może zostać zatrzymany przez system — po wybudzeniu ewentualnie uruchom zadanie ponownie lub dodaj w Harmonogramie zadań wyzwalacz „przy odblokowaniu stacji roboczej” (ręcznie w `taskschd.msc`). Duplikaty: skrypt instalacyjny ustawia **jedną** instancję (`IgnoreNew`). Gdy wcześniej używałeś ręcznego `Start-Process` z `python.exe`, ten sam proces kończysz w Menedżerze zadań po ścieżce do `.venv\Scripts\python.exe`.

**Uwaga:** wiele interwałów naraz = wiele zapytań do TV; przy problemach z limitem zostaw w `jobs` tylko wybrane TF.

## Wersja TypeScript (opcjonalnie)

Równoległy stack: `**scripts/tv_screenshot_ts/`** — ten sam pomysł, wymaga **Node.js**; patrz `README.md` w tym folderze.