# Inventory junctionów w root `DailySessionLogger_v2`

**Cel:** jedno miejsce z **każdą konkretną instancją** junctionu (nie tylko wzorzec `_*`) oraz statusem dostępu po teście.

**Mapowanie `Terminal\<HASH>` ↔ konto:** `docs/TERMINALS_INVENTORY.md` (wg `symlink.txt`).

**Reguły:** `.cursorrules_General` §**1d.9** — przed diagnozą polegającą na plikach: `Read` / listing po ścieżkach z tej tabeli; **`Glob` nie jest dowodem** braku pliku w junctionie.

---

## Status kolumny **Test dostępu**

| Wartość | Znaczenie |
|---------|-----------|
| **ACTIVE** | Ścieżka istnieje w workspace **i** daje się ją odczytać (`Test-Path` + próba `Get-ChildItem`); wpis potwierdzony skryptem `.\scripts\junctions\Test-JunctionAccess.ps1` (exit **0**). |
| **FAIL** | Brak folderu, martwy link lub błąd odczytu — napraw junction / manifest, nie zakładaj „braku plików” bez `Read`. |
| **—** | Nie wpisano jeszcze do `junctions_manifest.txt` / nie testowano w tej sesji. |

**Ostatnia pełna weryfikacja listy poniżej:** **2026-03-27** (`Test-JunctionAccess.ps1`: wszystkie wpisy z manifestu → **ACTIVE**; `Wyckoff_ALL` — listing PNG potwierdzony).

---

## Instancje junctionów (root repo) — lista pojedyncza + test

Kolejność: `data` → `logs_*` → `reports_*` / `Report*` → `scripts_*` → inne.

Uwaga operacyjna: `data\` jest tylko dla **plików CSV EA** i ich „stanów” (nie dla logów z MT5→Eksperci). Logi są w osobnych junctionach **`logs_<LOGIN>_...`** w rootcie.

| Względna ścieżka | Typ | Wskazuje typowo na | Uwagi | Test (`Test-JunctionAccess.ps1`) |
|------------------|-----|--------------------|-------|-------------------------------------|
| `data\` | junction (ReparsePoint) | `…\Terminal\<HASH>\MQL5\Files` | CSV EA (`DailySessionDeals*.csv`, `DailySessionSummary.csv`, …) | **ACTIVE** |
| `data\reports_10827887\` | folder pod `data\` | często ten sam cel co `Common\Files\reports_10827887` | HTML auto / podgląd pod junctionem `data\` | **ACTIVE** |
| `logs_10827887_terminal\` | junction | `…\<HASH>\MQL5\Logs` | Terminal **10827887** | **ACTIVE** |
| `logs_10827887_EA\` | junction | logi EA / wariant ścieżki (wg Twojego `mklink`) | **10827887** | **ACTIVE** |
| `logs_10827890_terminal\` | junction | `…\<HASH>\MQL5\Logs` | Terminal **10827890** | **ACTIVE** |
| `logs_10827890_EA\` | junction | j.w. | **10827890** | **ACTIVE** |
| `logs_10828174\` | junction | `…\<HASH>\MQL5\Logs` | **10828174** | **ACTIVE** |
| `logs_10828174_EA\` | junction | j.w. | **10828174** | **ACTIVE** |
| `logs_11693814\` | junction | `…\<HASH>\MQL5\Logs` | **11693814** | **ACTIVE** |
| `logs_11693814_EA\` | junction | j.w. | **11693814** | **ACTIVE** |
| `logs_11693817\` | junction | `…\<HASH>\MQL5\Logs` | **11693817** | **ACTIVE** |
| `logs_11693817_EA\` | junction | j.w. | **11693817** | **ACTIVE** |
| `logs_11720331\` | junction | `…\<HASH>\MQL5\Logs` | **11720331** | **ACTIVE** |
| `logs_11720331_EA\` | junction | j.w. | **11720331** | **ACTIVE** |
| `logs_11754867\` | junction | `…\<HASH>\MQL5\Logs` | **11754867** | **ACTIVE** |
| `logs_11754867_EA\` | junction | j.w. | **11754867** | **ACTIVE** |
| `reports_10827887\` | junction | `Common\Files\reports_10827887` **lub** `MQL5\Reports` | **Sprawdź target** — auto-HTML vs ręczny raport | **ACTIVE** |
| `reports_10828174\` | junction | j.w. | **10828174** | **ACTIVE** |
| `reports_11693814\` | junction | j.w. | **11693814** | **ACTIVE** |
| `reports_11693817\` | junction | j.w. | **11693817** | **ACTIVE** |
| `ReportHistoryAuto_10827887\` | junction | zwykle zapis `ExportDailyHistoryHtml` / Common | Nazwa poza wzorcem `reports_*` | **ACTIVE** |
| `Report_11720331\` | junction | raporty / pliki pod **11720331** | Nazwa poza wzorcem `reports_*` | **ACTIVE** |
| `scripts_10827887\` | junction | `…\<HASH>\MQL5\Scripts` | **10827887** | **ACTIVE** |
| `scripts_10828174\` | junction | j.w. | **10828174** | **ACTIVE** |
| `scripts_11693814\` | junction | j.w. | **11693814** | **ACTIVE** |
| `scripts_11693817\` | junction | j.w. | **11693817** | **ACTIVE** |
| `scripts_11720331_Reconcilled\` | junction | j.w. | **11720331** (wariant nazwy) | **ACTIVE** |
| `trading_strategy\` | junction | (poza MT5 — wg Twojego linku) | Nie logger; zostaje w manifeście pod pełny test dysku | **ACTIVE** |
| `Wyckoff_ALL\` | junction | typowo `D:\Trading\Wyckoff\Wyckoff_ALL` | Schematy Wyckoff: **`accu-1.png`…`accu-4.png`**, **`redistribution-1.png`…`redistribution-4.png`**, **`distribution-1.png`…`distribution-4.png`**, **`ReAccumulation-1.png`…`ReAccumulation-4.png`** (CamelCase), pomocniczo `Accu-1(Spring).webp`, `Distr-1(UTAD).webp`, `Distr-2(UT).jpg`, PDF/DOCX; **`.cursorrules_WyckOff`**. Weryfikacja: `.\scripts\junctions\Test-JunctionAccess.ps1` | **ACTIVE** |

> **Folder `scripts\` (bez loginu)** w rootcie to zwykły katalog repozytorium — **nie** junction; nie ma go w manifestcie.

---

## Utrzymanie (Ty + AI)

1. Nowy `mklink /J` / `New-Item -ItemType Junction` → **dopisz wiersz** w tabeli powyżej + **jedną linię** w `scripts/junctions/junctions_manifest.txt`.
2. Uruchom z rootu repo:

```powershell
.\scripts\junctions\Test-JunctionAccess.ps1
```

3. Zaktualizuj kolumnę **Test** na **ACTIVE** (lub **FAIL**) i datę **Ostatnia pełna weryfikacja** w nagłówku sekcji statusu.

---

## Skrót: polecenie testu

**Środowisko:** PowerShell, **katalog = root** `DailySessionLogger_v2`.

```powershell
cd "C:\Users\cewue\AppData\Roaming\MetaQuotes\Terminal\49C33A939697AEF354FFC02653AB58DE\MQL5\Experts\Advisors\DailySessionLogger_v2"
.\scripts\junctions\Test-JunctionAccess.ps1
```

Exit code **0** = każda ścieżka z manifestu — dostęp jak dla **ACTIVE** w tabeli.
