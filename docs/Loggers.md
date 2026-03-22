# Loggers – mapa logowan w DailySessionLogger_v2

Dokument opisuje obecnie wdrozone logowania (Print) powiazane z wykrywaniem zdarzen i zapisem plikow CSV. Logi EA: MQL5\Logs (zakladka Eksperci).

## 1. Account Age / reset / upsert
### 1.1 BalanceResetDetect
- Rola: Wykrywa DEAL_TYPE_BALANCE z komentarzem reset balance. Prefiks: BalanceResetDetect:
### 1.2 HandleBalanceReset
- Prefiksy: HandleBalanceReset:, AccountAgeReport:
### 1.3 UpsertAccountAgeRow
- Prefiks: UpsertAccountAgeRow:

## 2. Naglowki CSV (EnsureHeader*)
## 3. Sesja (EndSessionFinalize, AppendDailyFinalRow, NotifySessionEnd)
## 4. Deale (LogDealPerAccount, LogThreshold, ProcessCloseDeals)
## 5. Start EA i bledy
## 6. Szablon: Nazwa, Rola, Prefiks logow, Co loguje, Gdzie szukac.
