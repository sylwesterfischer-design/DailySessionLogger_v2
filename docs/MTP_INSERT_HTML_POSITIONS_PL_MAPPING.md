# Mapowanie: Raport Historii Trade (PL) — sekcja „Pozycje” → `DailySessionDeals<konto>.csv`

**Ta zmiana nie zmienia definicji pliku** `DailySessionDeals<konto>.csv`: nadal **18 kolumn** w kolejności jak w EA (`EnsureHeaderDailyDealsPerAccount`). Ten dokument opisuje **semantykę mapowania** przy imporcie z HTML (`insert_from_mt5_html.py`, `--layout positions-pl`).

**Powiązanie:** `docs/PYTHON_SETUP_WINDOWS.md` §4, `scripts/README.md`.

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

### 1.1. `minute_session_end` — ostrzeżenie o rozjazdach

Zgodnie z Twoją notatką: jeśli **`minute_session_end`** w pliku EA jest liczone **w kontekście `session_id`** (agregacja sesji), a w HTML masz tylko **czas zamknięcia pozycji**, może wystąpić **rozjazd** z logiką sesji EA.

- **Rekomendacja:** przy insertach z HTML **nie wymuszaj** `minute_session_end` jako „prawdy sesyjnej”, jeśli widzisz niespójności — zostaw pola sesyjne zgodnie z logiką skryptu (zera / minima z grupy) albo weryfikuj ręcznie po merge.
- Skrypt syntetycznie grupuje brakujące deale w sesje (`--session-mode`); to **nie** odtwarza w 100% sesji z EA.

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
