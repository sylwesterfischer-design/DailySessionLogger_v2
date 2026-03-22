# Skrypty pomocnicze (PowerShell / Python)

**Uwaga:** to **nie** jest folder **`MQL5\Scripts`** z terminala MT5. Skrypty reconcile `.mq5` kompilujesz w MetaEditorze i trzymasz pod `...\MQL5\Scripts` (u Ciebie często jako junction `scripts_<LOGIN>` — patrz `docs/SCRIPTS_JUNCTIONS.md`).

## Struktura

| Podfolder | Cel |
|-----------|-----|
| `junctions/` | `Create-ScriptsJunctions.ps1` — tworzy junctiony `scripts_<LOGIN>` z istniejących `logs_*` |
| `csv_repair_horizontal_summary/` | `repair_daily_session_summary.py` — naprawa poziomego rozjechania 14 kolumn w `DailySessionSummary.csv` |
| `csv_insert_from_mt5_html/` | `insert_from_mt5_html.py` — INSERT brakujących deali z raportu HTML MT5 → pliki `*_INSERT.csv` |
| *(korzeń `Experts\Advisors\`)* | **`ExportDailyHistoryHtml.mq5`** — EA: dzienny eksport HTML dealów do `Common\Files` + junction → `reports_<LOGIN>` — `docs/EXPORT_DAILY_HTML_JUNCTIONS.md` |

**Layout HTML:** `--layout deals-default` (eksport Deals, EN) lub `--layout positions-pl` (Raport Historii Trade PL, sekcja **Pozycje** — np. `reports_<login>/ReportHistory-*.html`). Szczegóły: `docs/PYTHON_SETUP_WINDOWS.md`.  
**Mapowanie kolumn (Pozycje → CSV):** `docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md`.

**Kodowanie:** MT5 często zapisuje HTML/CSV jako **UTF-16 LE** — `insert_from_mt5_html.py` to obsługuje (wcześniej tylko UTF-8 powodowało „puste” parsowanie).

Uruchamianie z **korzenia** repo (`DailySessionLogger_v2`):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\junctions\Create-ScriptsJunctions.ps1
py .\scripts\csv_repair_horizontal_summary\repair_daily_session_summary.py --help
py .\scripts\csv_insert_from_mt5_html\insert_from_mt5_html.py --help
```
