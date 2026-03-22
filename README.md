# DailySessionLogger_v2

EA MT5 (`DailySessionLogger_v2.mq5`) + dokumentacja + skrypty pomocnicze.

## Gdzie co leży (żeby menu Cursor było czytelne)

| Lokalizacja | Zawartość |
|-------------|-----------|
| **`GIT/`** | Wersjonowanie: `VERSION.md`, pełna **polityka Git** → `GIT/README.md` |
| **`docs/`** | Markdowny projektowe: `CHANGE_LOG.md`, `SCRIPTS_JUNCTIONS.md`, plany, weryfikacje → indeks `docs/README.md` |
| **`scripts/`** | **PowerShell / Python** (nie `MQL5\Scripts`): junctiony, naprawa CSV, INSERT z HTML → `scripts/README.md` |
| **Korzeń** | EA `.mq5`, `.mqproj`, `.code-workspace`, `.cursorrules*`, `.gitignore` |

Szczegóły reguł dla AI: `.cursorrules`, `.cursorrules_General`, itd.  
**Onboarding Cursor / Ollama / ograniczenia:** `.cursorrules-cursor-init-config`, `docs/MT5_DAILY_HTML_EXPORT_NOTE.md`.

---

## Git

Zobacz **`GIT/README.md`** (branch przed zmianą, `git init`, MetaEditor vs Clone, remote).

## Naprawa „poziomego’’ `DailySessionSummary.csv`

**Python** — `scripts/csv_repair_horizontal_summary/repair_daily_session_summary.py`. EA nie naprawia starych zepsutych bajtów w CSV sam z siebie.

1. Kopia / `--backup`  
2. `--dry-run`  
3. Uruchomienie bez `--dry-run` (lub `-o` na nowy plik)

```powershell
py .\scripts\csv_repair_horizontal_summary\repair_daily_session_summary.py `
  -i "$env:APPDATA\MetaQuotes\Terminal\Common\Files\DailySessionSummary.csv" `
  --only-date 2026-03-20 --only-konto 11693814 --backup
```

## INSERT brakujących wierszy z raportu HTML MT5

`scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py` → pliki `*_INSERT.csv`. Zawsze najpierw **`--dry-run`**.

- **`--layout deals-default`** — typowy eksport sekcji Deali (EN).
- **`--layout positions-pl`** — **Raport Historii Trade** (PL), sekcja **Pozycje** (np. junction `reports_10828174\ReportHistory-10828174.html`).

**Python:** instalacja i PATH → **`docs/PYTHON_SETUP_WINDOWS.md`**.

```powershell
py .\scripts\csv_insert_from_mt5_html\insert_from_mt5_html.py `
  --layout positions-pl `
  --html "reports_10828174\ReportHistory-10828174.html" `
  --konto 10828174 `
  --deals-in "data\DailySessionDeals10828174.csv" `
  --dry-run
```

## Kopia CSV przed wdrożeniem

Git **nie zastępuje** backupu wielkich CSV w `Common\Files` (patrz `.gitignore`). Ręczna kopia przed podmianą `.ex5` zalecana.
