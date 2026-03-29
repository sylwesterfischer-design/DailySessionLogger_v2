# Mapowanie: Raport Historii Trade (PL) — sekcja „Pozycje” → `DailySessionDeals<konto>.csv`

**Ta zmiana nie zmienia definicji pliku** `DailySessionDeals<konto>.csv`: nadal **18 kolumn** w kolejności jak w EA (`EnsureHeaderDailyDealsPerAccount`). Ten dokument opisuje **semantykę mapowania** przy imporcie z HTML (`insert_from_mt5_html.py`, `--layout positions-pl`).

**Stały układ kolumn:** raport HTML zapisany z klienta MT5 (*Historia konta → raport HTML*) ma **powtarzalny** zestaw kolumn w sekcji „Pozycje”; mapowanie poniżej jest **źródłem prawdy** dla tego przepływu. Inny wariant (`--layout deals-default`) dotyczy wyłącznie uproszczonej tabeli z auto-eksportu `ExportDailyHistoryHtml.mq5`, nie menu MT5.

**Powiązanie:** `docs/PYTHON_SETUP_WINDOWS.md` §4, `scripts/README.md`.

### Retrofit *rozwiązania* a pliki `*_pyTEST.csv` / `*_INSERT.csv`

- **Źródło** dla insertu jest nadal **raport HTML** (porównanie ticketów z produkcyjnym `DailySessionDeals<konto>.csv`). Plików `*_pyTEST.csv` ani `*_INSERT.csv` **nie** używa się jako zamiennika HTML — to tylko **wyjścia** (test lub kopia przed podmianą produkcji).
- **Retrofit** oznacza tu **zmianę implementacji** (np. wczesny filtr `--only-date` w parserze, strumień wierszy `<tr>`), żeby pipeline był wydajny i przewidywalny jak „jeden dzień” w Excelu — **bez** podmiany źródła danych na CSV pomocniczy.

---

## 1. Tabela mapowania (załącznik użytkownika)

| Kolumna / pole w HTML (Raport Historii, „Pozycje”) | Kolumna w CSV EA | Uwagi |
|---------------------------------------------------|------------------|--------|
| **Czas** (pierwszy — otwarcie) | *(bezpośrednio nie wszystkie pola)* | Skrypt do deduplikacji i `deal_time` używa **czasu zamknięcia** (drugi „Czas”), patrz §3. |
| **Pozycja** | **`deal_ticket`** | U Ciebie **przyjęte założenie:** numer z **Pozycja** = ten sam identyfikator co **`deal_ticket`** w wierszach CSV z EA — wtedy insert po ticketach ma sens także z `--layout positions-pl`. |
| **Instrument** | **`symbol`** | |
| **Typ** | **`direction`** | `buy` / `sell` (+ polskie synonimy w parserze). |
| **Wolumen** | **`volume`** | |
| **Cena** (pierwsza — otwarcie) | *(domyślnie w skrypcie: cena zamknięcia, kol. 10)* | W Twojej tabeli „cena” → `price`: **upewnij się**, czy chodzi o cenę **otwarcia** czy **zamknięcia**; skrypt `positions-pl` bierze **cenę zamknięcia** (kolumna HTML nr 10) jako `price` w wierszu insertu. |
| **Zysk** | **`profit_only`** | |
| **Swap** | — | **Nie mapujemy** do CSV (brak dedykowanej kolumny w schemacie 18-kolumnowym). |
| **Prowizja** | — | **Nie mapujemy** do CSV. |
| **Czas** (drugi — **zamknięcie**) | sens **`deal_time`** (i ewent. spójność z **`minute_session_end`**) | W CSV `deal_time` jest w formacie jak EA (`DD.MM.YYYY HH:MM`). |

### 1.1. Sesje, `minute_session_*`, `session_id` (positions-pl)

**Ta zmiana nie zmienia definicji pliku** — nadal 18 kolumn; zmienia się tylko **sposób wypełnienia** pól sesyjnych przy `--layout positions-pl`.

- **`deal_time` / `price` / `profit_only`:** wiersz CSV = **jedna pozycja z HTML** (nie agregat).  
  - `deal_time` = **czas zamknięcia** z HTML (kol. 9), po `FloorToMinute` jak w EA.  
  - `price` = **cena zamknięcia** (kol. 10) — **różne wiersze w tej samej sesji mogą mieć różne ceny**; to nie jest „jedna cena całej sesji”.  
  - `profit_only` = **Zysk** (kol. 13) — powinno być **1:1** z komórką w tabeli „Pozycje” dla tego samego wiersza (po normalizacji liczby).
- **`session_id`, `minute_session_start`, `minute_session_end`, `max_session_profit`:** skrypt **symuluje** zachowanie EA (`.cursorrules_General` §18): zdarzenia **+1** przy **czasie otwarcia** (kol. 0), **−1** przy **czasie zamknięcia** (kol. 9); przy tym samym timestampie sortowanie: **najpierw zamknięcia, potem otwarcia** (flat zanim startuje kolejna sesja). Dla każdego **dnia kalendarzowego** (data wg **czasu zamknięcia**) symulacja jest osobna.  
  - `max_session_profit` na każdym wierszu sesji = **suma `profit_only` wszystkich pozycji w tej sesji** (jak sens kolumny w EA przy agregacji na sesję).  
  - **`session_id` z insertu nie musi być równe** `session_id` z pliku EA — to **nowe ID** liczone od `max(session_id)` w istniejącym CSV + kolejne sesje zrekonstruowane z HTML.

**Porównanie z raportem HTML konta** (np. `reports_<LOGIN>/ReportHistory-<LOGIN>.html`): źródłem „prawdy” dla pojedynczego wiersza są **komórki HTML** (ticket, czasy, cena zamk., zysk). Pola **czysto sesyjne** (DD, margin, …) insert **nie odtwarza** z HTML — zostają zera / pusto wg schematu.

---

## 2. Po co w ogóle `deal_ticket`? Czy można pominąć?

**Nie chodzi o „przepis” z MT5, tylko o mechanikę skryptu:**

1. Skrypt **porównuje** zestaw identyfikatorów z HTML z kolumną **`deal_ticket`** w istniejącym CSV.
2. Wiersze, których „ticketu” **nie ma** jeszcze w CSV, traktuje jako **kandydatów do dopisania** (INSERT).
3. Bez takiego klucza skrypt **nie wie**, które wiersze HTML są już w pliku, a które brakują — dopisałby duplikaty albo wszystko od zera.

**„Pozycja” vs `deal_ticket`:**  
Jeśli na Twoim koncie / typie konta (np. hedge vs netting) i w eksporcie EA **numer pozycji = ten sam numer co `deal_ticket`** w CSV — używasz **`Pozycja` jako tego klucza** i **nie musisz** przełączać się na angielski raport **Deals**.  
Gdyby któryś wiersz miał **inny** numer w historii deali niż w kolumnie Pozycja, deduplikacja by się **pomyliła** — wtedy sensowny jest raport **Deals** (`--layout deals-default`) lub weryfikacja ticketów w MT5.

---

## 3. Indeksy kolumn w HTML (dla developera — `positions-pl`)

Po spłaszczeniu komórek `<td>` w wierszu tabeli (kolejność jak w MT5):

| Indeks (0-based) | Zawartość |
|-------------------|-----------|
| 0 | Czas otwarcia |
| 1 | **Pozycja** (mapowane jako ticket) |
| 2 | Instrument |
| 3 | Typ |
| 4 | (często puste / ukryte) |
| 5 | Wolumen |
| 6 | Cena otwarcia |
| 7–8 | S/L, T/P |
| **9** | **Czas zamknięcia** → używany jako `deal_time` w insertcie |
| **10** | **Cena zamknięcia** → `price` w insertcie |
| 11 | Prowizja (nie mapujemy do osobnej kolumny CSV) |
| 12 | Swap (nie mapujemy) |
| **13** | **Zysk** → `profit_only` |

---

## 4. Nagłówek CSV (18 kolumn) — bez zmian kolejności

```
date;konto;session_id;deal_time;deal_ticket;symbol;direction;volume;price;profit_only;max_session_equity_drawdown;max_session_profit;max_total_lot;max_margin_burned;max_session_equity_burned_percent;account_reset;minute_session_start;minute_session_end
```

Kolumny sesyjne / DD przy imporcie z HTML są **uzupełniane wg reguł skryptu** (zera lub wartości grupujące), bo HTML **Pozycje** ich nie dostarcza w pełni.

---

## 5. QA: jak ręcznie zweryfikować wiersz względem `ReportHistory-<LOGIN>.html`

1. Otwórz w przeglądarce **ten sam plik HTML**, który podałeś w `--html` (np. junction `reports_10827887/ReportHistory-10827887.html`).
2. Znajdź w sekcji **„Pozycje”** wiersz o **`Pozycja`** = `deal_ticket` z CSV.
3. Porównaj:
   - **drugi czas** w wierszu (zamknięcie) ↔ **`deal_time`** w CSV (format `DD.MM.YYYY HH:MM`);
   - **Zysk** ↔ **`profit_only`**;
   - **cena zamknięcia** (kol. 10) ↔ **`price`**.
4. **`minute_session_start` / `minute_session_end`:** dla `positions-pl` wynikają z **symulacji flat** (§1.1), nie z pojedynczej komórki HTML — sprawdzasz spójność **wewnątrz wygenerowanego CSV** (start ≤ end, ta sama para dla wszystkich deali w danym `session_id`).

**Uwaga czasu:** wartości w HTML są w **czasie zapisanym przez MT5 w raporcie** (zwykle czas serwera brokera). Insert **nie konwertuje stref** — kopiowanie stringów do CSV w formacie jak EA.
