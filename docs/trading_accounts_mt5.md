# Instalacje MT5 — konta objęte listą (zaznaczone na niebiesko)

**Ten dokument nie zmienia schematu** żadnych plików CSV EA — to **rejestr** kont / instalacji; nagłówki plików loggera pozostają zgodne z `EnsureHeaderDailyDealsPerAccount` / `EnsureHeaderDailyGlobal` w kodzie.

- **Zakres:** foldery **zaznaczone na niebiesko** w Eksploratorze; kolumna **`DailySessionDeals*.csv`** i **pełny login** tam, gdzie da się **jednoznacznie** spiąć końcówkę z nazwy folderu z plikiem z załącznika (`DailySessionDeals10827890.csv` itd.).
- **Waluta:** jeśli w nazwie folderu / etykiecie arkusza **nie** ma jawnego **EUR** / **USD** / **GBP**, przyjmujemy domyślnie **PLN** (Twoja reguła robocza).
- **Current balance:** plik **`DailySessionDeals<LOGIN>.csv` ma 18 kolumn i NIE zawiera `end_balance`** — saldo bierz z **ostatniego wiersza** `DailySessionSummary.csv` dla tego **`konto`** (kolumny `date` + `end_balance`), z **MT5** (*Widok → Toolbox → Handel*), albo z **AccountAgeReport** jeśli tam prowadzisz bieżące saldo. W tabeli poniżej: **`—`** = do uzupełnienia przy następnej aktualizacji (AI uzupełnia, gdy ma dostęp do CSV przez workspace).

## Obowiązek utrzymania (AI + Ty)

- Przy **nowym koncie**, nowym `DailySessionDeals*.csv`, zmianie folderu MT5, zmianie waluty — **zaktualizuj ten plik** (reguła **§1d.8** w `.cursorrules_General`).
- Datę ostatniej ręcznej weryfikacji sald możesz dopisać w stopce.

**Ostatnia aktualizacja struktury dokumentu:** 2026-03-13 (kolumny waluta / balance / CSV).

---

## Bezpieczeństwo — hasła

- **Haseł nie zapisujemy w repozytorium.** Tylko loginy i serwery.

---

## Tabela: folder Eksploratora ↔ typ ↔ login ↔ waluta ↔ balance

**Pełny login z załącznika CSV:** tam gdzie w nazwie folderu była tylko **końcówka** (`_890`, `_814`, …), dopasowano **jeden** plik `DailySessionDeals*.csv` z Twojego zrzutu Common, którego numer **kończy się** tą samą końcówką (np. `…890` → **10827890**). Jeśli na zrzucie **nie było** takiego pliku — login zostaje jak w folderze / do weryfikacji w MT5.

| Folder (nazwa w Eksploratorze) | Typ | Login | Waluta | Current balance | `DailySessionDeals*.csv` | Uwagi |
|----------------------------------|-----|-------|--------|-----------------|---------------------------|--------|
| `MetaTrader 5 — kopia (DEMO-01_10934764)-master` | Demo | 10934764 | PLN | — | — | suffix „-master” |
| `MetaTrader 5 — kopia (DEMO-02_10828908)` | Demo | 10828908 | PLN | — | — | |
| `MetaTrader 5 — kopia (DEMO-03_10828174)` | Demo | 10828174 | PLN | — | tak → `DailySessionDeals10828174.csv` | |
| `MetaTrader 5 — kopia (DEMO-04_10957585)` | Demo | 10957585 | PLN | — | — | Arkusz: Client Account 2 |
| `MetaTrader 5 — kopia (DEMO-05_10827887)` | Demo | 10827887 | PLN | — | tak → `DailySessionDeals10827887.csv` | Arkusz Client 5 = **10627887** vs folder **10827887** → weryfikuj w MT5 |
| `MetaTrader 5 — kopia (DEMO-06_890)` | Demo | **10827890** | PLN | — | tak → `DailySessionDeals10827890.csv` | było `_890` → pełny nr z pliku na zrzucie |
| `MetaTrader 5 — kopia (DEMO-07_814)` | Demo | **11693814** | PLN | — | tak → `DailySessionDeals11693814.csv` | było `_814` → pełny nr z pliku na zrzucie |
| `MetaTrader 5 — kopia (DEMO-08_817)` | Demo | **11693817** | PLN | — | tak → `DailySessionDeals11693817.csv` | było `_817` → pełny nr z pliku na zrzucie |
| `MetaTrader 5 — kopia (DEMO-09_331)` | Demo | **11720331** | PLN | — | tak → `DailySessionDeals11720331.csv` | było `_331` → pełny nr z pliku na zrzucie |
| `MetaTrader 5 — kopia (DEMO-10_867)` | Demo | **11754867** | PLN | — | tak → `DailySessionDeals11754867.csv` | było `_867` → pełny nr z pliku na zrzucie |
| `MetaTrader 5 — kopia (DEMO-11_456_HERO)` | Demo | *(MT5)* | PLN | — | — | końcówka **456** — **brak** na zrzucie pliku `DailySessionDeals*456*.csv`; pełny login **tylko z MT5** (np. arkusz: Client 10 **11754456** — nie było na załączniku CSV) |
| `MetaTrader 5 — kopia (DEMO-EUR_824)` | Demo | 824 | **EUR** | — | — | `_824` — brak pliku `*824.csv` na zrzucie; jeśli login pełny inny, popraw po MT5 |
| `MetaTrader 5 — kopia (Live 2-Two_11711840)` | Live | 11711840 | PLN | — | — | Arkusz: PROD Live 2 |
| `MetaTrader 5 — kopia (Live 3-THREE_11710937)` | Live | 11710937 | PLN | — | — | Arkusz 11711937 vs folder → weryfikuj |
| `MetaTrader 5 — kopia (Live 4-Four_18495775)` | Live | 18495775 | PLN | — | — | Arkusz 18435775 vs folder → weryfikuj |
| `MetaTrader 5 — kopia (Live 5-Five_18495776)` | Live | 18495776 | PLN | — | — | |
| `MetaTrader 5 — kopia (Live 6-Six_18495777)` | Live | 18495777 | PLN | — | — | |
| `MetaTrader 5 — kopia (Live 7-SEVEN)` | Live | *(MT5)* | PLN | — | — | dopisz login z terminala |
| `MetaTrader 5 — kopia (Live 8-Eight)` | Live | *(MT5)* | PLN | — | — | j.w. |
| `MetaTrader 5 — kopia (Live 9-Nine)` | Live | *(MT5)* | PLN | — | — | j.w. |
| `MetaTrader 5 — kopia (Live 10-Ten)` | Live | *(MT5)* | PLN | — | — | j.w. |
| `MetaTrader 5 — kopia (LiveMaster-10849931)` | Live | 10849931 | PLN | — | — | MASTER PROD |

---

## Arkusz Vantage — loginy, serwery, waluta (bez haseł)

### Demo — `VantageInternational-Demo`

| Etykieta w arkuszu | Login | Serwer | Waluta (wg etykiety) |
|--------------------|-------|--------|----------------------|
| Client Account 1 | 10628308 | VantageInternational-Demo | PLN |
| Client Account 2 | 10957585 | VantageInternational-Demo | PLN |
| Client Account 3 | 12534764 | VantageInternational-Demo | PLN |
| Client Account 4 | 10828174 | VantageInternational-Demo | PLN |
| Client Account 5 | 10627887 | VantageInternational-Demo | PLN |
| MASTER DEMO | 10627859 | VantageInternational-Demo | PLN |
| Client Account 5 - USD | 11058063 | VantageInternational-Demo | **USD** |
| Client Account 5 - EUR1 | 11232175 | VantageInternational-Demo | **EUR** |
| Client Account 5 - EUR2 | 11232187 | VantageInternational-Demo | **EUR** |
| Client Account 5 - GBP | 11232175 | VantageInternational-Demo | **GBP** |
| Client Account 6 - new | 11653514 | VantageInternational-Demo | PLN |
| Client Account 7 - new | 11653517 | VantageInternational-Demo | PLN |
| Client Account 8 - new | 11715331 | VantageInternational-Demo | PLN |
| Client Account 9 - new | 11754337 | VantageInternational-Demo | PLN |
| Client Account 10 - new | 11754456 | VantageInternational-Demo | PLN |
| Client Account 11 - EURO new | 12537624 | VantageInternational-Demo | **EUR** |

**Uwaga:** EUR1 i GBP w zrzucie miały **ten sam login 11232175** — weryfikacja u brokera.

**Uwaga Client 4:** OCR mógł pokazać 16828174 — przyjęto **10828174**.

### Live — `VantageInternational-Live 4`

| Etykieta w arkuszu | Login | Serwer | Waluta |
|--------------------|-------|--------|--------|
| MASTER PROD | 10849931 | VantageInternational-Live 4 | PLN |
| PROD Live 2 - Two | 11711840 | VantageInternational-Live 4 | PLN |
| PROD Live 3 - Three | 11711937 | VantageInternational-Live 4 | PLN |
| PROD Live 4 - Four | 18435775 | VantageInternational-Live 4 | PLN |
| PROD Live 5 - Five | 18495776 | VantageInternational-Live 4 | PLN |
| PROD Live 6 - Six | 18495777 | VantageInternational-Live 4 | PLN |

---

## Jak uzupełnić **Current balance** (dla AI i dla Ciebie)

1. Otwórz **`DailySessionSummary.csv`** (wspólny plik, `FILE_COMMON`) — znajdź **ostatni chronologicznie** wiersz z `konto == <LOGIN>` → weź **`end_balance`**.
2. Alternatywnie: saldo z okna **MT5** dla tego loginu.
3. **Nie** szukaj salda w **`DailySessionDeals<LOGIN>.csv`** — tam **nie ma** kolumny salda (tylko deal / sesja / margin % itd.).

---

## `ExportDailyHistoryHtml.mq5` — gdzie to wgrać

- **Źródło w repo:** `ExportDailyHistoryHtml.mq5`.
- **Cel:** `MQL5\Experts\` **tej** kopii MT5 + **kompilacja** w jej MetaEditorze.
- **HTML → Python:** `docs/EXPORT_DAILY_HTML_JUNCTIONS.md`.
- **PowerShell:** `docs/POWERSHELL_COMMANDS.md`.
