# Risk Sizing by Account (LIVE)

Dokument operacyjny: ile ryzykować per konto i jaki `max_total_lot` utrzymywać w LIVE, na podstawie Twojego stylu gry i historii z `DailySessionSummary.csv` / `DailySessionDeals*.csv`.

---

## 1) Najważniejsza zasada

- Dla LIVE używamy przelicznika:
  - **bazowo: `0.35-0.40 lot / 1k balance`**
  - **sufit operacyjny: `0.40 lot / 1k`** (czyli `4.0 lot / 10k`)
- `**0.50 lot / 1k**` traktujemy jako zbyt agresywne dla standardowej pracy LIVE.

W praktyce:

`max_total_lot_live = balance * 0.0004`

Przykład:

- `40,000` -> `16.0 lot`
- `50,000` -> `20.0 lot`

---

## 2) Strefy ryzyka (LIVE)

Liczone względem `ratio = max_total_lot / start_balance`.

- **GREEN (normal):** do `0.030%` (`<= 3.0 lot / 10k`)
- **YELLOW (ostrożnie):** `0.030%-0.040%` (`3.0-4.0 lot / 10k`)
- **ORANGE (wysokie):** `0.040%-0.050%` (`4.0-5.0 lot / 10k`)
- **RED (strefa śmierci):** `> 0.050%` (`> 5.0 lot / 10k`)

Uwaga praktyczna: dla konta `40k` poziom `20 lot` to `5 lot / 10k` -> **RED**.

---

## 3) Tabela limitów per balance


| Balance konta | Limit konserwatywny (`0.35/1k`) | Limit bazowy (`0.40/1k`) | Limit agresywny (`0.50/1k`) |
| ------------- | ------------------------------- | ------------------------ | --------------------------- |
| 20,000        | 7.0 lot                         | 8.0 lot                  | 10.0 lot                    |
| 30,000        | 10.5 lot                        | 12.0 lot                 | 15.0 lot                    |
| 40,000        | 14.0 lot                        | 16.0 lot                 | 20.0 lot                    |
| 50,000        | 17.5 lot                        | 20.0 lot                 | 25.0 lot                    |
| 75,000        | 26.25 lot                       | 30.0 lot                 | 37.5 lot                    |
| 100,000       | 35.0 lot                        | 40.0 lot                 | 50.0 lot                    |


Rekomendacja dla LIVE: trzymać się kolumny `0.35/1k` lub `0.40/1k`.

---

## 4) Wnioski z danych (skrót)

- W danych historycznych bez FAIL górny sensowny zakres był blisko **~4.14 lot / 10k** (p95).
- Występowały sesje FAIL także przy niskim `total_lot/balance`, gdy rynek i sekwencja pozycji robiły gwałtowny ruch przeciw pozycji.
- Dlatego sam ratio lot/equity nie wystarcza: potrzebny jest margines bezpieczeństwa i twarde limity.

Wniosek operacyjny:

- **LIVE default:** `0.40 / 1k` jako sufit,
- **po przekroczeniu 4.0 lot / 10k** ograniczać nowe wejścia,
- **5.0 lot / 10k** traktować jako strefę awaryjną.

---

## 5) Reguła wykonywania (prosta)

Przed dokładaniem pozycji:

1. Policz `current_total_lot` (otwarte pozycje po filtrach strategii).
2. Policz `limit = balance * 0.0004`.
3. Jeśli `current_total_lot >= limit`, nie otwieraj kolejnej pozycji.
4. Jeśli `current_total_lot >= 0.9 * limit`, tylko redukcja ryzyka / hedge defensywny (bez dokładania kierunku).

---

## 6) Proponowane alerty (LIVE)

- `>= 70% limitu` -> alert informacyjny (YELLOW)
- `>= 90% limitu` -> alert ostrzegawczy (ORANGE)
- `>= 100% limitu` -> alert krytyczny (RED)

Dodatkowo (już wdrożone): alerty co `10 lot` (`10Lots Opened!`, `20Lots Opened!`, ...).

---

## 7) Alerty Tier1/Tier2/Tier3 (per balance)

Te alerty skaluje się **liniowo** od `balance` i dotyczą **limitów lotów**, nie tylko „okrągłych” progów (10/20/30…).

### 7.1 Definicje tierów

Liczymy 3 limity:

- **Tier1 (standard):** `balance / 1000 * 0.35`
- **Tier2 (base):** `balance / 1000 * 0.40`
- **Tier3 (aggressive):** `balance / 1000 * 0.50`

Czyli równoważnie:

- Tier1 = `balance * 0.00035`
- Tier2 = `balance * 0.00040`
- Tier3 = `balance * 0.00050`

### 7.2 Treść notyfikacji

- `LOT TIER1 ALERT | Standard LOT limit reached`
- `LOT TIER2 ALERT | Base LOT limit reached`
- `LOT TIER3 ALERT | Aggressive LOT limit reached`

W implementacji do notyfikacji dopinamy też kontekst (`konto`, `balance`, `total_lot`, `limit`), żeby od razu było widać „ile brakuje / ile przekroczone”.

### 7.3 Przykłady skalowania (odpowiedź na 25k)

Przy `balance = 25,000`:

- Tier1: `25 * 0.35 = 8.75 lot`
- Tier2: `25 * 0.40 = 10.00 lot`
- Tier3: `25 * 0.50 = 12.50 lot`

Czyli **pierwszy alert nie jest stały** (np. `0.7 lot`), tylko zależy od balansu i rośnie liniowo wraz z kontem.

---

## 8) Zakres dokumentu

- Dokument dotyczy kont **LIVE/produkcyjnych**.
- Dla DEMO można stosować wyższy limit testowy, ale bez przenoszenia 1:1 na LIVE.
- Przy zmianie stylu gry lub zmienności rynku zaktualizuj wartości i datę przeglądu.

---

## 9) Data i status

- Data opracowania: **2026-03-27**
- Status: **wersja operacyjna (do stosowania od razu)**

