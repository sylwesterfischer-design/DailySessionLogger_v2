# DailySessionLogger_v2: Reconcile -> Flush Plan (A/B/C)

Ten dokument opisuje bezpieczną procedurę:

- jednorazowej rekonsiliacji braków z historii MT5
- przygotowania danych w plikach `*_RECONCILED_*`
- testowego flush do plików z końcówką `*_FLUSH_TEST*`
- docelowego flush do realnych plików CSV

## Kontekst: co rekoncyliujemy

1. `DailySessionDeals<konto>.csv` (per konto) – dopisujemy brakujące deal ticket-y
2. `DailySessionSummary.csv` (globalny summary) – dopisujemy / korygujemy wiersze sesji (klucz `date;konto;session_id`)

Cel: uniknąć duplikatów i “rozjechania” `start_balance/end_balance` na kolejnych sesjach.

## Ważne: schemat CSV nie zmienia się

Flush używa schematów dokładnie takich jak w core:

`DailySessionSummary.csv` ma 14 kolumn w tej kolejności:
`date;konto;session_id;start_balance;end_balance;max_session_equity_drawdown;max_session_profit;max_single_lot;max_total_lot;max_margin_burned;max_session_equity_burned_percent;account_reset;minute_session_start;minute_session_end`

`DailySessionDeals<konto>.csv` ma schemat zgodny z EA (18 kolumn).

## Gdzie są skrypty (folder MT5)

Skrypty muszą być skompilowane w profilu terminala, w którym odpalasz konto.

1. W MT5 wejdź w `File -> Open Data Folder`
2. Znajdź folder `MQL5\Scripts`
3. Skopiuj pliki:
   - `DailySessionReconcile_Delta_11720331.mq5`
   - `DailySessionSummary_Flush_Reconciled.mq5`
   - `DailySessionDeals_Flush_Reconciled.mq5`
4. W tym samym profilu terminala uruchom kompilację w MetaEditorze (poniżej).

## Compile gate (warunek widoczności w MT5)

MT5 `Navigator -> Scripts` pokazuje skrypt dopiero po kompilacji (powstaje `*.ex5`).

Procedura:
1. Otwórz `.mq5` w MetaEditorze (z folderu `MQL5\Scripts` danego profilu)
2. Upewnij się, że kompilacja kończy się sukcesem
3. Wciśnij `F7`
4. Sprawdź, że w tym samym folderze obok `.mq5` pojawił się plik `DailySession... .ex5`
5. Dopiero wtedy wróć do MT5 i sprawdź `Navigator -> Scripts`

Jeśli skrypt nie pojawia się:
- upewnij się, że skopiowałeś go do właściwego `Terminal\<hash>\` (ten hash musi odpowiadać profilowi, gdzie stoi konto)
- ponów `F7` i sprawdź czy powstało `*.ex5` w tym samym folderze
- zrestartuj MT5 (często pomaga, gdy Explorer zmienił pliki)

## A) Reconcilacja delta (dane źródłowe -> pliki *_RECONCILED)

Uruchom:
- `DailySessionReconcile_Delta_11720331.mq5`

Zasada bezpieczeństwa:
- ten etap nie modyfikuje produkcyjnych plików `DailySessionSummary.csv` ani `DailySessionDeals11720331.csv`;
- jego zadaniem jest stworzenie osobnych plików “po naprawie” z końcówką `*_RECONCILED*`, które będą wejściem do flush.

Co ma powstać:
- `DailySessionDeals11720331_RECONCILED.csv`
- `DailySessionSummary_RECONCILED_11720331_<DD-MM-YYYY>.csv`

Parametry (domyślne):
- `InpLogin = 11720331`
- `InpDryRun = false` (dopuszczalne najpierw `true`, jeśli chcesz zobaczyć log bez zapisu)

## B) Flush testowy (pliki *_RECONCILED -> *_FLUSH_TEST)

To jest etap bezpieczny: nie modyfikuje realnych CSV (ani `DailySessionSummary.csv`, ani `DailySessionDeals11720331.csv`).

Jeśli pliki `*_RECONCILED*` już istnieją (w `data\` dla Twojego profilu/terminala), etap A możesz pominąć i przejść od razu do flush testowego.

### B1) Summary test

Uruchom:
- `DailySessionSummary_Flush_Reconciled.mq5`

Ustawienia:
- `InpLogin = 11720331`
- `InpDateTag = "18-03-2026"` (tu podajesz datę zakresu)
- `InpApplyToReal = false`

Co powstanie:
- `DailySessionSummary_FLUSH_TEST_11720331_18-03-2026.csv`

### B2) Deals test

Uruchom:
- `DailySessionDeals_Flush_Reconciled.mq5`

Ustawienia:
- `InpLogin = 11720331`
- `InpApplyToReal = false`

Co powstanie:
- `DailySessionDeals11720331_FLUSH_TEST.csv`

## C) Flush produkcyjny (po akceptacji testów)

Jeżeli testy są OK (w szczególności):
- liczba deal ticktów 1:1 z raportem HTML
- `start_balance/end_balance` w `DailySessionSummary_FLUSH_TEST_...` nie “cofa się” i jest spójne w łańcuchu sesji

to dopiero wtedy uruchom:

### C1) Summary real
- `DailySessionSummary_Flush_Reconciled.mq5`
- `InpApplyToReal = true`

### C2) Deals real
- `DailySessionDeals_Flush_Reconciled.mq5`
- `InpApplyToReal = true`

## Minimalna weryfikacja po B (test)

1. Sprawdź `DailySessionDeals..._FLUSH_TEST.csv`:
   - brak duplikatów po `deal_ticket`
2. Sprawdź `DailySessionSummary_FLUSH_TEST...csv`:
   - dla klucza `date;konto;session_id` wartości `start_balance/end_balance` powinny tworzyć spójny ciąg

## Logowanie i diagnostyka (co sprawdzać)

1. W `DailySessionLogger_v2` core masz `Print()` w miejscach krytycznych
2. W reconcilu masz dodatkowe `Print()` dla “mismatch” w summary (gdy start/end nie pasują)
3. Flush skryptów wypisuje `DONE ... replaced_rows / written_rows`

## Checklist: plan powinien być wykonany w tej kolejności

1. A: `DailySessionReconcile_Delta_11720331.mq5` -> `*_RECONCILED`
2. B: flush test summary + flush test deals -> `*_FLUSH_TEST`
3. C: po akceptacji: flush real summary + flush real deals

