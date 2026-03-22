# Account Age Report – weryfikacja i aktualna definicja

Dokument opisuje **obecnie wdrożoną** logikę raportu AccountAgeReport.csv oraz jego definicję zgodną z .cursorrules. Aktualizowany po każdej zmianie w tej funkcjonalności.

---

## 1. Definicja pliku AccountAgeReport.csv (SCHEMA UPGRADE: period_uid)

- **Plik:** `AccountAgeReport.csv` (Terminal Common\Files), separator `;`, pierwsza linia `sep=;`.
- **Znaczenie wiersza:** 1 wiersz = 1 okres życia konta – od **resetu balansu** do **końca życia** (FAIL: equity/balance < 1000 PLN lub stop-out). Wiersze historyczne **nie są usuwane ani nadpisywane** przez inne okresy.
- **Klucz wiersza (twardy):** `period_uid` (unikalny ID okresu życia konta).  
  Format: `login_<server_seconds>` (deterministyczny, odporny na formatowanie tekstu w CSV/Excel).
  - RESET tworzy nowy `period_uid` i otwiera nowy cykl update.  
  - FAIL zamyka cykl (`g_account_age_reported = true`) i kończy aktualizacje dla tego `period_uid`.  
  - Każdy UPDATE po SessionID musi aktualizować **wyłącznie** wiersz z bieżącym `period_uid` (nie wolno aktualizować innego).

---

## 2. Kiedy powstaje NOWY wiersz (początek życia konta)

**Zasada (intencja):** dla danego loginu w jednym „życiu konta” w CSV jest **jeden aktywny wiersz** (ten sam `period_uid`), aktualizowany po każdej sesji. **Nowy** wiersz — wyłącznie po **(A) resecie balansu brokera** albo **(B) FAIL** zakończenia okresu (i skasowaniu sidecara), **nie** z powodu samego restartu EA.

- **Trigger A — reset konta:** wykryty **reset balansu** w `HandleBalanceReset()` (deal typu BALANCE z komentarzem „reset balance” / „balance reset” – `IsBalanceResetDeal()`). `UpsertAccountAgeRow()` dopisuje wiersz z **nowym** `period_uid`.
- **Trigger B — nowy okres po FAIL:** gdy `g_day_failed` i sesja się finalizuje, `g_account_age_reported = true` i **kasowany** jest plik stanu `AccountAgeActive_<login>.state`; przy **kolejnym** `OnInit` (brak sidecar) powstaje **nowy** `period_uid` = `login` + `_` + `TimeCurrent()` — to jest **nowy** wiersz w CSV (kolejny okres po upadku konta).
- **NIE jest triggerem nowego wiersza:** **restart EA**, przeładowanie wykresu, zmiana TF, ponowne załączenie tego samego EA na tym samym koncie **bez** resetu balansu i **bez** FAIL — wtedy ma być **ta sama** aktualizacja **tego samego** `period_uid` / wiersza. Wcześniejsza wersja kodu **łamała tę zasadę** (nowy UID po każdym starcie EA → **APPEND** zamiast UPDATE) — to **bug**, nie zmiana reguł biznesowych; poprawka: **`AccountAgeActive_<login>.state` + `HydrateAccountAgeFromCsv` + `OnDeinit`** → **`docs/CHANGE_LOG.md` ID-25**, ROOT-CAUSE: *restart EA zerował globals*.
- **NIE jest triggerem:** skrypty reconcile, `PENDING_WRITE`, edycja innych CSV — **nie** wołają `HandleBalanceReset` ani `UpsertAccountAgeRow` z zewnątrz EA.

### 2.1 Plik stanu `AccountAgeActive_<login>.state` (Common\Files)

- **Cel:** globalne MQL5 zerują się przy **każdym** restarcie EA / przeładowaniu na wykres. Bez trwałego stanu EA po starcie ustawiał `g_account_start_time = TimeCurrent()` → **nowy** `period_uid` → `UpsertAccountAgeRow` **nie** znajdował starego UID w pliku → **APPEND** kolejnego wiersza; poprzedni wiersz przestawał być aktualizowany („zamrożony”). Łańcuch `account_end_balance` ≈ `account_start_balance` następnego wiersza to typowo **ciągłość konta**, nie reset brokera.
- **Zawartość (3 linie tekstu):** `period_uid`, sekundy serwera startu okresu, `account_start_balance` początku okresu.
- **Zapis:** po udanym `UpsertAccountAgeRow` (okres aktywny), w `OnInit` po wznowieniu/utworzeniu okresu, w `OnDeinit` jeśli okres nadal aktywny.
- **Kasowanie:** przy końcu życia okresu (`g_day_failed` w `EndSessionFinalize`) — żeby kolejny start EA nie podłączył się pod zamknięty cykl.

### 2.2 Hydrate z CSV po restarcie

- Jeśli istnieje wiersz z tym samym `period_uid`, EA wczytuje z niego główne liczniki (trades, sessions, sumy przybliżone pod `profit_factor` itd.), żeby pierwszy zapis po restarcie **nie wyzerował** agregatów.

### 2.3 Zachowanie w `HandleBalanceReset()`

- Po zapisie segmentu FAILED (`AppendDailyFinalRow()`) i restarcie liczenia dnia ustawiane są zmienne nowego okresu życia:
  - `g_account_start_time`, `g_account_start_balance`, `g_account_max_equity`,
  - `g_session_end_time = 0` (żeby w nowym wierszu `account_end_date` = `account_start_date`, `session_id` = 0),
  - zerowanie liczników: `g_active_trading_days`, `g_total_trades`, `g_win_trades`, `g_sum_profit`, `g_sum_loss`, serie, `g_total_trade_duration_sec`, `g_total_sessions`, `g_account_age_reported = false`.
- Na końcu bloku Account Age wywoływane jest `UpsertAccountAgeRow()` — tworzy **nowy** wiersz w pliku (dopisywany na końcu, bo klucz jeszcze nie istnieje).
- W pliku: brak wiersza z danym `period_uid` → dopisanie nowego wiersza; wcześniejsze wiersze (tego samego lub innych kont) pozostają bez zmian.

---

## 3. Kiedy wiersz jest AKTYWNY i jak jest aktualizowany

- Wiersz jest **aktywny**, dopóki `g_account_age_reported == false`.
- **Źródło aktualizacji:** każda zakończona sesja (`EndSessionFinalize`), gdy `open_cnt == 0` i sesja się finalizuje.
- **Zachowanie w EndSessionFinalize** (przed `NotifySessionEnd`):
  - Jeśli `g_account_age_reported == false` → wywołanie `**UpsertAccountAgeRow()`**.
- **UpsertAccountAgeRow():**
  - Buduje linię CSV z aktualnych globali (**BuildAccountAgeLine()**).
- Szuka w pliku wiersza o kluczu `period_uid`; jeśli znajdzie – **nadpisuje tę linię**, jeśli nie – dopisuje na końcu. Inne wiersze nie są zmieniane.
  - Przed upsertem globalne liczniki Account Age są już zaktualizowane (m.in. w `ProcessCloseDeals`, `UpdateSessionMetrics`: `g_total_sessions++`, `g_account_max_equity`, `g_total_trades`, `g_win_trades`, serie, duration, `g_active_trading_days` itd.).
- W czasie życia konta w pliku jest **dokładnie jeden aktywny wiersz** na konto/okres, aktualizowany po każdej zakończonej sesji; wiersze historyczne są **zamrożone** i nigdy nadpisywane.

---

## 4. Kiedy wiersz KOŃCZY życie (staje się historyczny)

- **Warunek końca życia:** `g_day_failed == true` (ustawiane gdy equity < 1000 PLN lub balance < 1000 PLN, ewentualnie stop-out) **oraz** zakończenie sesji (`EndSessionFinalize` dla sesji z `open_cnt == 0`).
- **Zachowanie w EndSessionFinalize przy końcu życia:**
  - Najpierw wywoływane jest **UpsertAccountAgeRow()** – ostatnia aktualizacja wiersza (wszystkie 23 pola z finalnymi wartościami).
  - Zaraz potem ustawiane jest `**g_account_age_reported = true`**.
- Od tego momentu **UpsertAccountAgeRow()** nie modyfikuje już tego wiersza (na początku funkcji: `if(g_account_age_reported) return;`). Wiersz pozostaje w pliku jako historyczny i **nie może być przez nikogo ani nic nadpisany**. Kolejny reset tego konta tworzy **nowy wiersz** z nową datą startu.

---

## 5. Nagłówek pliku i naprawa nagłówka

- **EnsureHeaderAccountAge():** Tworzy plik **tylko gdy nie istnieje**. Zapisuje `sep=;\r\n` oraz wiersz nagłówka 23 kolumn. **Logowanie:** `Print("EnsureHeaderAccountAge: file does not exist, creating with header: ...")` oraz `Print("EnsureHeaderAccountAge: header written OK for ...")`.
- **UpsertAccountAgeRow():** Wywołuje `EnsureHeaderAccountAge()`. W gałęziach „pierwsze utworzenie pliku” (FileOpen READ zwraca INVALID_HANDLE lub `FileSize(h) <= 0`) **również zapisuje** `sep=;` + nagłówek + pierwszy wiersz – aby obie ścieżki tworzące plik dawały poprawny nagłówek.
- **Twarda kontrola przy odczycie:** Po wczytaniu zawartości pliku w `UpsertAccountAgeRow()` sprawdzane jest:
  - czy `nlines >= 2` oraz czy `lines[0] == "sep=;"` i `lines[1] == expected_header`.
  - Jeśli **nie** – nagłówek jest **naprawiany w miejscu** (`lines[0]`, `lines[1]` lub przy `nlines < 2` odbudowa tablicy z trzema liniami: sep, nagłówek, new_line), a przy zapisie zapisywany jest już poprawny plik.
  - **Logowanie:** `Print("UpsertAccountAgeRow: header mismatch or missing, repairing header in ...")` oraz w każdym upsercie `Print("UpsertAccountAgeRow: upsert OK ... header_fixed=true/false")`.

### 5b. Zasada CORE: nie nadpisywać wierszy innych kont

- **Definicja (niezmienna):** Wiersze innych kont **NIGDY** nie są usuwane ani nadpisywane. W pliku może być wiele wierszy (po jednym na każdy okres życia każdego konta); upsert zmienia **wyłącznie** linię o kluczu `(g_login, account_start_date)`.
- **Normalizacja zakończeń linii:** Przed `StringSplit(content, '\n', lines)` w `UpsertAccountAgeRow()` wykonywane jest `StringReplace(content, "\r\n", "\n")` oraz `StringReplace(content, "\r", "\n")`, żeby pliki z różnymi zakończeniami linii (Windows/Unix) nie dawały `nlines == 1` i przypadkowego zastąpienia całego pliku jednym wierszem.
- **Zabezpieczenie przy błędzie parsowania:** Gdy po odczycie pliku `nlines < 2` **ale** `sz > 250` (plik zawierał prawdopodobnie dane innych kont), **nie** zastępujemy pliku – dopisujemy **tylko** nowy wiersz na końcu pliku (SEEK_END) i kończymy. W logach: `WARNING nlines=... but sz=... – possible other accounts data, APPEND only for konto=...`.
- **Logowanie (diagnostyka nadpisywania):** W `UpsertAccountAgeRow()` logowane są: `nlines`, `sz`, `konto`, `key_start` po odczycie; przy aktualizacji istniejącego wiersza: `UPDATING existing row at line i for konto=...`; przy dopisywaniu: `APPENDING new row (total data rows now N) for konto=...`; przy zastąpieniu minimalnego pliku: `replaced minimal file (nlines<2, sz<=250) for konto=...`.

---

## 6. Schemat pliku (24 kolumny – dodano period_uid)

Kolejność kolumn (separator `;`):

```
period_uid;konto;account_start_date;account_end_date;session_id;
account_start_balance;account_end_balance;max_equity_history;
max_drawdown_pln;total_lot_current_max;account_age_days;
active_trading_days;total_net_profit;max_drawdown_percent;
profit_factor;total_trades;win_rate_percent;avg_trade_profit;
max_consecutive_wins;max_consecutive_losses;avg_trade_duration_min;
most_traded_symbol;market_session_failure;total_sessions
```

- **period_uid:** twardy, unikalny identyfikator okresu życia konta w formacie `login_<server_seconds>`. RESET otwiera nowy `period_uid`, FAIL zamyka cykl update.
- **konto:** numer loginu MT5 (`ACCOUNT_LOGIN`).
- **account_start_date:** lokalny czas PL rozpoczęcia okresu życia konta (moment zarejestrowanego resetu balansu).
- **account_end_date:** lokalny czas PL końca ostatniej zakończonej sesji w tym okresie; przy świeżym okresie (bez zakończonej sesji) = `account_start_date`.
- **session_id:** ID ostatniej zakończonej sesji w tym okresie; przy nowym wierszu (brak zakończonej sesji) = `0`.
- **account_start_balance:** saldo konta na starcie okresu życia konta (po resecie), w walucie konta.
- **account_end_balance:** aktualne saldo konta przy zapisie wiersza (po ostatniej zakończonej sesji), w walucie konta.
- **max_equity_history:** maksymalne equity konta osiągnięte w całym okresie życia konta (nie może być logicznie mniejsze niż historyczne equity, ale może być mniejsze/większe od `account_end_balance` w zależności od przebiegu).
- **max_drawdown_pln:** maksymalny (najbardziej ujemny) drawdown w PLN w okresie – oparty na `g_session_max_dd` z ostatniej sesji. Zapisywany jako liczba ujemna.
- **total_lot_current_max:** maksymalny łączny wolumen pozycji (`g_session_max_total_lot`) osiągnięty w pojedynczej sesji w całym okresie.
- **account_age_days:** pełne dni między `g_account_start_time` a bieżącym końcem życia okresu (lub aktualnym czasem, jeśli sesja nadal trwa).
- **active_trading_days:** liczba dni, w których w okresie wystąpiły transakcje (liczone po `DayStartLocal`).
- **total_net_profit:** różnica `account_end_balance - account_start_balance` (wynik netto całego okresu życia konta).
- **max_drawdown_percent:** maksymalny drawdown w % w odniesieniu do `account_start_balance`, liczony jako `(|g_session_max_dd| / account_start_balance) * 100` i zapisywany jako tekst z sufiksem `%` (np. `12,34%`).
- **profit_factor:** klasyczny profit factor z całego okresu: `g_sum_profit / g_sum_loss`; gdy `g_sum_loss == 0` i `g_sum_profit > 0` przyjmowana wartość `999,99`; przy braku transakcji `0,00`.
- **total_trades:** łączna liczba transakcji w okresie (`g_total_trades`) – liczone po wszystkich dealach BUY/SELL (nie liczba sesji).
- **win_rate_percent:** odsetek wygrywających transakcji w okresie w %: `(g_win_trades / g_total_trades) * 100`, zapisywany jako tekst z sufiksem `%` (np. `66,67%`).
- **avg_trade_profit:** średni zysk/strata na transakcję: `total_net_profit / g_total_trades` (0,00 gdy brak transakcji).
- **max_consecutive_wins:** maksymalna długość serii kolejnych wygrywających transakcji w okresie (`g_max_consecutive_wins`).
- **max_consecutive_losses:** maksymalna długość serii kolejnych przegrywających transakcji w okresie (`g_max_consecutive_losses`).
- **avg_trade_duration_min:** średni czas trwania jednej transakcji w minutach: `g_total_trade_duration_sec / 60 / g_total_trades` (0,00 gdy brak transakcji).
- **most_traded_symbol:** symbol, na którym wystąpiło najwięcej transakcji w danym okresie (aktualnie w kodzie zostawione puste; pole zarezerwowane pod przyszłe rozszerzenie licznika symboli).
- **market_session_failure:** sesja rynku, w której nastąpił koniec życia konta (lub ostatnia zakończona sesja) – wyliczana przez `GetMarketSessionFailure()` na podstawie lokalnego czasu PL. Obecne mapowanie przedziałów czasu (PL):
  - `Sydney` – 22:00–01:00 (22:00–24:00 oraz 00:00–01:00),
  - `Tokyo/Sydney` – 01:00–07:00,
  - `Tokyo` – 07:00–09:30,
  - `Tokyo/London` – 09:00–09:30,
  - `London` – 09:30–13:00,
  - `London/NewYork` – 13:00–17:30,
  - `NewYork` – 17:30–22:00,
  - `Other` – każdy czas poza powyższymi przedziałami.
- **total_sessions:** licznik zakończonych sesji w okresie (`g_total_sessions`), zwiększany w `UpdateSessionMetrics()` przed `EndSessionFinalize()` i zerowany w `HandleBalanceReset()` przy starcie nowego życia konta.

---

## 7. Funkcje w kodzie (odniesienie)


| Funkcja                                         | Rola                                                                                                                                                                 |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **EnsureHeaderAccountAge()**                    | Tworzy plik z nagłówkiem tylko gdy plik nie istnieje. Loguje tworzenie.                                                                                              |
| **GetMarketSessionFailure(datetime end_local)** | Zwraca sesję rynku (Tokyo, London, NewYork, Overlap, Other) na podstawie czasu PL.                                                                                   |
| **BuildAccountAgeLine()**                       | Buduje jedną linię CSV (23 kolumny) z aktualnych globali. Używana przez UpsertAccountAgeRow.                                                                         |
| **UpsertAccountAgeRow()**                       | Główna funkcja zapisu: tworzy/aktualizuje wiersz po kluczu (konto + account_start_date). Sprawdza i naprawia nagłówek przy odczycie. Loguje tworzenie/repair/upsert. |
| **AppendAccountAgeRowFinal()**                  | Legacy – nieużywana w głównym flow; pozostawiona ewentualnie do jednorazowego „finalnego” zapisu.                                                                    |


---

## 8. Próg FAIL i brakujące flagi (stan na dziś)

- **Próg końca życia konta:** **1000 PLN** (ustalone). `g_day_failed` ustawiane w `UpdateSessionMetrics()` i `OnTimer()` przy `eq < 1000.0 || bal < 1000.0`.
- **g_session_closed_so** / **g_seen_stop_out:** W kodzie nigdzie nie są ustawiane na `true` (tylko odczyt). Kolumna `account_closed_stop_out` w SessionDD_Thresholds może być pusta do momentu dodania ustawiania przy Margin Level ≤ 20% lub DEAL_REASON_STOPOUT.

---

## 9. Wpływ na istniejące 4 raporty

- **AccountAgeReport.csv** jest jedynym nowym plikiem. Schematy i logika **DailySessionSummary.csv**, **DailySessionDeals_****.csv**, **SessionDD_Thresholds.csv**, **DAILY_ACCOUNTSDETAILS.csv** nie są zmieniane.
- Żadna z funkcji core (AppendDailyFinalRow, LogDealPerAccount, LogThreshold, EnsureHeader* dla tych plików) nie została zmodyfikowana pod kątem Account Age – tylko dodane wywołania UpsertAccountAgeRow i aktualizacje liczników w ProcessCloseDeals / UpdateSessionMetrics / HandleBalanceReset / EndSessionFinalize.

---

## 10. Checklist przy zmianach (dla AI)

Przy każdej zmianie dotyczącej Account Age raportu w podsumowaniu należy podać:

- Czy zmieniony został schemat/nagłówek AccountAgeReport.csv (tak/nie, jak).
- Czy zmiana może wpłynąć na generowanie 4 istniejących raportów.
- Czy wiersze historyczne (zamrożone) pozostają kompatybilne.
- Czy logowanie tworzenia/naprawy nagłówka i upsertu jest zachowane lub rozszerzone.

