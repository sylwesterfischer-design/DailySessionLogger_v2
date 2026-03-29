# Log modeli (OCR) z zrzutów TradingView → Excel

Po każdym **udanym** PNG z `scheduled_screenshots.py` (gdy w `capture_schedule.json` jest `models_log.enabled: true`) skrypt:

1. Uruchamia **Tesseract OCR** na wycinkach obrazu (legenda wskaźników + obszar wykresu).
2. Wyciąga tekst typu **reaccumulation-1**, **redistribution-2** (regex na wynik OCR) → kolumna **`current_model`**; poprzednia wartość z ostatniego wiersza → **`previous_model`**.
3. Liczy wystąpienia **HH, LH, LL, HL** w tekście OCR z wykresu. Przy **pierwszym** zrzucie danego TF tylko ustawia stan bazowy (kolumny HH–HL **puste**). Przy kolejnych — jeśli liczba wzrosła, zapisuje **`+N`** w odpowiedniej kolumnie (np. `+1`); brak wzrostu → **puste** (zgodnie z opisem „new_generated”).

Stan liczników jest w pliku **`ocr_state.json`** obok pliku Excel (nie edytuj ręcznie w trakcie działania harmonogramu).

## Wymagania

- **Python:** `pip install -r scripts/tv_screenshot/requirements.txt` (openpyxl, pytesseract, Pillow).
- **Program Tesseract OCR** (osobno od `pip`): **bez `tesseract.exe` nie powstanie** ani `trading_models.xlsx`, ani `ocr_state.json` — skrypt kończy się na OCR. Windows: [UB-Mannheim/tesseract](https://github.com/UB-Mannheim/tesseract/wiki) + **PATH**, albo pełna ścieżka w JSON: `models_log.tesseract_cmd` (np. `C:\\Program Files\\Tesseract-OCR\\tesseract.exe`). Diagnoza: `scripts/tv_screenshot/models_excel_cli.log` (linia `RuntimeError: Brak Tesseract OCR` lub traceback).
- **PATH systemowy (Windows):** w „Zmiennych środowiskowych” **dodaj** wpis `C:\Program Files\Tesseract-OCR` **jako kolejną linię** na liście ścieżek w `Path` — **nie zastępuj** całej zmiennej `Path` jednym katalogiem (wtedy znikają m.in. `System32` i przestają działać podstawowe polecenia). Bezpieczniej: zostaw PATH w spokoju i ustaw wyłącznie `tesseract_cmd` w JSON.
- Opcjonalnie język: `ocr_lang` — domyślnie `eng`. Dla `pol` doinstaluj `pol.traineddata` do `tessdata`.

## Konfiguracja (`capture_schedule.json`)

Skopiuj blok `models_log` z `capture_schedule.example.json` i ustaw:

| Klucz | Znaczenie |
|--------|-----------|
| `enabled` | `true` — włącza dopisywanie po zrzucie |
| `excel_path` | Ścieżka do `.xlsx` (względna od rootu repo lub absolutna) |
| `schema_template` | Szablon przy pierwszym utworzeniu pliku (kopiowany 1:1). W repo: `models_logs/schema_template_tv_models.xlsx` |
| `tesseract_cmd` | Pusty = szukanie `tesseract` w PATH |
| `ocr_legend_crop` | `[x0,y0,x1,y1]` ułamki 0–1 obrazu — lewa góra (legenda wskaźników) |
| `ocr_chart_crop` | Ułamki — obszar wykresu (etykiety HH/LH/…) |

**Uwaga:** OCR na wykresie jest **przybliżony**. Jeśli model się nie wykrywa, dopasuj `ocr_legend_crop` / `ocr_chart_crop` do Twojego layoutu (rozdzielczość 1920×1080 jak w `viewport`).

## Junction: jeden folder `models_logs` dla dwóch terminali MT5

Masz repo pod **różnymi** `Terminal\<hash>\` (np. Cursor vs drugi profil). Żeby Excel zawsze trafiał w:

`C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\0E812ED0A250D901020B93B704737346\MQL5\Experts\Advisors\DailySessionLogger_v2\models_logs`

utwórz **junction** w drugim repo (np. pod profilem z Cursor), wskazujący na ten **fizyczny** katalog.

**W PowerShell (uruchom jako zwykły użytkownik; jeśli `models_logs` już istnieje jako zwykły folder — usuń go lub zmień nazwę najpierw):**

```powershell
$Target = "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\0E812ED0A250D901020B93B704737346\MQL5\Experts\Advisors\DailySessionLogger_v2\models_logs"
$Link   = "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2\models_logs"

New-Item -ItemType Directory -Force -Path $Target | Out-Null
if (Test-Path $Link) { Remove-Item $Link -Force -Recurse }
New-Item -ItemType Junction -Path $Link -Target $Target
```

- **`$Target`** — katalog docelowy (tu zapisujesz Excel + `ocr_state.json`).
- **`$Link`** — ścieżka w repo, z którego uruchamiasz `scheduled_screenshots.py` (podstaw swój `Terminal\<hash>` jeśli inny).

Odwrotny kierunek (link w `0E81…` → folder w `49C33…`) też jest możliwy; ważne, by **jeden** katalog był „prawdziwym” a drugi junction.

Skrypt pomocniczy: `scripts/junctions/Create-ModelsLogsJunction.ps1` (te same zmienne na górze pliku).

## Test ręczny (jeden PNG)

Z rootu repo (`cd` do `DailySessionLogger_v2`, nie z `C:\Windows\System32`):

```powershell
.\.venv\Scripts\pip install -r scripts\tv_screenshot\requirements.txt
.\.venv\Scripts\python scripts\tv_screenshot\models_excel_logger.py --png "docs\tv_scheduled\M5_20260329_194305_chart.png" --tf M5
```

**Log przy uruchomieniu z CLI:** `scripts/tv_screenshot/models_excel_cli.log` (append). Harmonogram zrzutów nadal zapisuje szczegóły wywołań OCR/Excel w **`docs/tv_scheduled/tv_capture.log`** (linie `models_excel ok` / `models_log FAIL`).

## Powiązane

- `scripts/tv_screenshot/README.md` — harmonogram zrzutów
- `scripts/tv_screenshot/models_excel_logger.py` — implementacja
