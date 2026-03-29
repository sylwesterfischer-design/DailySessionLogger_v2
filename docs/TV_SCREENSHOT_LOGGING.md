# Logi — zrzuty TradingView (Playwright)

Są **dwa osobne pliki logów** — odpowiadają **różnym skryptom**. Nie zamieniają się nawzajem.

## Tabela: który plik, który proces

| Plik (domyślnie) | Skrypt | Zawartość (skrót) |
|------------------|--------|-------------------|
| `scripts/tv_screenshot/tv_save_session.log` | `save_tv_storage_state.py` | Start z `use_chrome_channel=true/false` (bundled Chromium vs `--chrome`), `goto` na TradingView, komunikat po załadowaniu strony, moment zapisu `tv_storage_state.json` po **Enter**, rozmiar pliku; przy błędzie — pełny traceback |
| `docs/tv_scheduled/tv_capture.log` | `scheduled_screenshots.py` | Start procesu (PID, `exe`, `cwd`), lista jobów TF, każdy **CAPTURE** (URL, ścieżka PNG, bajty lub FAIL), ewentualny **FATAL** |

Ścieżkę **`tv_capture.log`** można zmienić w `capture_schedule.json` kluczem **`log_file`** (ścieżka względem rootu repo `DailySessionLogger_v2`).

Plik **`tv_save_session.log`** jest zawsze obok `save_tv_storage_state.py` (`scripts/tv_screenshot/`).

## Po co to jest

- Przy uruchomieniu z **harmonogramu Windows** używane jest **`pythonw.exe`** — **brak okna konsoli**, stdout/stderr często **nigdzie nie widać**. Jedyny stały ślad to plik **`tv_capture.log`** (oraz Menedżer zadań / Historia zadania w `taskschd.msc`).
- **`save_tv_storage_state.py`** zapisuje do **`tv_save_session.log`** od razu przy starcie — widać, czy doszło do otwarcia przeglądarki i do `goto`, oraz czy zapis sesji się powiódł.

## Git

W `.gitignore` jest wpis **`*.log`** — pliki logów **nie powinny** być commitowane.

## Log OCR → Excel (`models_log`)

Gdy w `capture_schedule.json` jest `models_log.enabled: true`, po udanym zrzucie w **`tv_capture.log`** pojawiają się linie **`models_excel ok`** (model, HH–HL) albo **`models_log FAIL`** / traceback.

Ręczny test **`models_excel_logger.py`** z CLI zapisuje szczegóły do **`scripts/tv_screenshot/models_excel_cli.log`** (osobno od harmonogramu).

## Diagnostyka (nie zastępuje logów)

Skrypt **`scripts/tv_screenshot/diagnose_tv_session.py`** wypisuje na stdout JSON (m.in. UA, `navigator.webdriver`, liczbę cookies TradingView) — pomaga odróżnić problem sesji od headless / polityki strony. Szczegóły: `scripts/tv_screenshot/README.md` (sekcja o trybie podglądu i `headed`).

## Pełna instrukcja zrzutów i sesji TV

`scripts/tv_screenshot/README.md`
