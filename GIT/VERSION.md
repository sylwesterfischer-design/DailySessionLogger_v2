# Wersja projektu DailySessionLogger_v2

Format: **MAJOR.MINOR.PATCH** (opisowo w commitach / `docs/CHANGE_LOG.md`).

| Wersja   | Data       | Skrót zmian |
|----------|------------|-------------|
| **4.1.5** | (ustaw przy tagu) | Docs: `GITHUB_SETUP_STEP_BY_STEP.md`, Python `.msix` w `PYTHON_SETUP_WINDOWS.md` — ID-28. |
| **4.1.4** | (ustaw przy tagu) | Alerty `TOTAL_LOT_ALERT` 50/100/150/200 (sesja, ten sam filtr symbolu co sesja) — ID-27. |
| **4.1.3** | (ustaw przy tagu) | INSERT HTML: `--layout positions-pl`; `docs/PYTHON_SETUP_WINDOWS.md`; `GIT/README` GitHub↔Cursor (ID-26). |
| **4.1.2** | (ustaw przy tagu) | Account Age: `AccountAgeActive_<login>.state` + hydrate z CSV + `OnDeinit` — brak fałszywych nowych wierszy przy restarcie EA (ID-25). |
| **4.1.1** | (ustaw przy tagu) | Ochrona zapisu `DailySessionSummary.csv` (14 kolumn), flush `g_daily_global_file`, logi flush; skrypt Stage A: `MT5AUDIT4-SUMMARYGUARD` + opcjonalny abort nadpisania reconciled summary. |
| 4.1.0   | wcześniej  | Diagnostyka reconcile (`STAGE_DIAG` w `MT5_CHECK`), ID-18. |

**Zasada:** po każdej większej zmianie podbij PATCH (lub MINOR), wpisz wiersz powyżej i dopisz wiersz do `docs/CHANGE_LOG.md`.

**Git (lokalnie):** dotyczy **całego kodu projektu**, przede wszystkim `DailySessionLogger_v2.mq5` — nie tylko skryptów reconcile. Przed zmianą: branch lub tag „baseline’’ (`GIT/README.md`).
