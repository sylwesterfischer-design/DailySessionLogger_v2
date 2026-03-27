//+------------------------------------------------------------------+
//| DailySessionLogger_v2.mq5                                        |
//| - Daily summary CSV (1 row/day)                                  |
//| - Session drawdown thresholds CSV (rows per threshold hit)        |
//|                                                                  |
//| User rules:                                                      |
//| - PROFIT ONLY: DEAL_PROFIT (no swap/commission)                  |
//| - Session = from first open position to flat (0 positions)        |
//|   Session ends in the minute when account becomes flat           |
//| - Log drawdown thresholds per session: every -1000 PLN            |
//| - Track max single lot and max total lots simultaneously in session|
//| - konto = ACCOUNT_LOGIN                                           |
//+------------------------------------------------------------------+
#property strict
input string InpDealsFile      = "DAILY_ACCOUNTSDETAILS.csv";
input int    InpTimerSeconds   = 1;
input long   InpMagicFilter    = -1;     // -1 = all
input string InpSymbolFilter   = "";     // "" = all
input double InpDDStep         = 1000.0; // threshold step in account currency
// Diagnostyka i retry: deal profit-only (DEAL_PROFIT) bywa aktualizowany z opóznieniem po zamknieciu pozycji.
// Jeśli sesja konczy sie przy total_profit_only==0, a w historii sa deale OUT/INOUT z DEAL_PROFIT==0,
// to robimy krotki retry skanu, zeby nie przegapic "póznio aktualizowanych" profitów.
input int    InpLateProfitRetrySeconds       = 15; // ile sekund czekac przed 2-tym skanem
input int    InpLateProfitRetrySampleLimit   = 12; // ile ticketów p==0 wypisac (tylko gdy podejrzewamy rozjazd)

input string InpDailyFile      = "DailySessionSummary.csv";
input string InpThreshFile     = "SessionDD_Thresholds.csv"; //Ĺťeby DailySessionSummary.csv trzymaĹ historiÄ wielu dni (1 wiersz/dzieĹ/konto, z przecinkami), a perâkonto i deals zostaĹy bez zmian, zrĂłb trzy rzeczy.

// --- live update dziennego wiersza ---
int g_live_update_counter = 0;   // liczymy ticki timera
int g_live_update_period  = 3600; // sekundy (1 godzina przy InpTimerSeconds=1)

// >>> ZMIENNA GLOBAL <<<
string g_daily_file = "";
string g_daily_global_file = "DailySessionSummary.csv";

// Kolejka pending dla sytuacji, gdy Excel/innny program blokuje zapisy do CSV.
// Zasada: jeśli nie da się dopisać do docelowego pliku (FileOpen -> INVALID_HANDLE),
// zapisujemy gotowy wiersz do pliku kolejki w Common/Files i flushujemy przy następnym uruchomieniu.
string g_pending_write_suffix = ".__PENDING_WRITE__";

int g_pending_flush_counter = 0;
int g_pending_flush_period_seconds = 20; // co ile sekund próbujemy flushować pending queue

// --- anti-duplicate for DAILY_ACCOUNTSDETAILS ---
ulong   g_last_deal_ticket_logged = 0;
long    g_last_deal_time_msc_logged = 0;

// -------------------- helpers --------------------
datetime DayStart(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
}
datetime FloorToMinute(datetime t)
{
   return (datetime)((long)t - ((long)t % 60));
}
string DateStr(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
}
string MinuteStr(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02d %02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min);
}

string StripBOM(string s)
{
   // usuĹ UTF-8 BOM, jeĹli Excel zapisaĹ CSV jako UTF-8
   if(StringLen(s) > 0 && (ushort)StringGetCharacter(s, 0) == 0xFEFF)
      return StringSubstr(s, 1);
   return s;
}

// helper wykrywajÄcy BALANCE RESET w historii (DEAL_TYPE_BALANCE + comment "reset balance ...")
bool IsBalanceResetDeal(ulong deal_ticket)
{
   long type = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
   if(type != DEAL_TYPE_BALANCE) return false;

   string c = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
   StringToLower(c);

   // pod TwĂłj screen:
   if(StringFind(c, "reset balance") >= 0)  return true;
   if(StringFind(c, "balance reset") >= 0)  return true;

   return false;
}

// ---------------------------------------------------------
// Wykrywanie resetu balansu w historii (Balance Operation)
// Cel: mieć jedno, deterministyczne miejsce, które wywołuje HandleBalanceReset()
// Logi: Print(...) trafiają do MQL5\Logs (Experts) i są kluczowe diagnostycznie
// ---------------------------------------------------------
bool DetectAndHandleBalanceReset()
{
   // Ogranicz sprawdzanie historii, żeby nie mielić co sekundę bez potrzeby
   static datetime last_check_server = 0;
   datetime now_server = TimeCurrent();
   if(last_check_server > 0 && (now_server - last_check_server) < 10)
      return false;
   last_check_server = now_server;

   // Wyznacz okno historii do skanowania (wystarczy kilka dni wstecz)
   datetime from_server = (g_last_balance_reset_time > 0)
                          ? (g_last_balance_reset_time - 60)
                          : (now_server - 7 * 24 * 60 * 60);
   datetime to_server   = now_server;

   // Diagnostyka: pokaż parametry skanowania
   Print("BalanceResetDetect: scan history konto=", (string)g_login,
         " from=", TimeToString(from_server, TIME_DATE|TIME_MINUTES),
         " to=",   TimeToString(to_server,   TIME_DATE|TIME_MINUTES),
         " last_reset_time=", TimeToString(g_last_balance_reset_time, TIME_DATE|TIME_MINUTES));

   // Sprawdź historię deal'i w oknie czasowym
   if(!HistorySelect(from_server, to_server))
   {
      Print("BalanceResetDetect: HistorySelect failed err=", GetLastError(),
            " konto=", (string)g_login);
      return false;
   }

   int total = HistoryDealsTotal();
   if(total <= 0)
      return false;

   // Szukamy NAJNOWSZego resetu w oknie (żeby nie „cofać” czasu)
   datetime best_reset_time = 0;
   string   best_comment    = "";

   for(int i = 0; i < total; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      // Filtr: tylko deale typu BALANCE z komentarzem reset
      if(!IsBalanceResetDeal(deal_ticket))
         continue;

      datetime t = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
      string   c = HistoryDealGetString(deal_ticket, DEAL_COMMENT);

      // Pomijamy reset, który już był obsłużony
      if(g_last_balance_reset_time > 0 && t <= g_last_balance_reset_time)
         continue;

      if(t > best_reset_time)
      {
         best_reset_time = t;
         best_comment    = c;
      }
   }

   // Jeśli znaleziono nowy reset – uruchom core ścieżkę resetu
   if(best_reset_time > 0)
   {
      Print("BalanceResetDetect: FOUND new reset konto=", (string)g_login,
            " reset_time=", TimeToString(ToLocal(best_reset_time), TIME_DATE|TIME_MINUTES),
            " comment=", best_comment);

      // Core: reset dnia + start nowego okresu życia konta + UpsertAccountAgeRow()
      HandleBalanceReset(best_reset_time, best_comment);
      return true;
   }

   return false;
}

// --- TIME MODE: local PC time (PL) ---
bool InpUseLocalTime = true; // moĹźesz zrobiÄ input, ale tu dajÄ jako staĹe

datetime NowTime()
{
   return (InpUseLocalTime ? TimeLocal() : TimeCurrent());
}

// offset local vs server (do konwersji czasĂłw z historii deal'i)
long LocalServerOffsetSec()
{
   return (long)(TimeLocal() - TimeCurrent());
}

datetime ToLocal(datetime server_time)
{
   if(!InpUseLocalTime) return server_time;
   return (datetime)((long)server_time + LocalServerOffsetSec());
}

datetime DayStartLocal(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
}

datetime FloorToMinuteLocal(datetime t)
{
   return (datetime)((long)t - ((long)t % 60));
}

string MinuteStrLocal(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%02d.%02d.%04d %02d:%02d", dt.day, dt.mon, dt.year, dt.hour, dt.min);
}

string DateStrLocal(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
}

// --- helper do liczb (Excel PL: przecinek zamiast kropki) ---
string NumStr(double v, int digits=2)
{
   string s = DoubleToString(v, digits);
   StringReplace(s, ".", ",");
   return s;
}
// -------------------- session id helpers --------------------

// plik pomocniczy trzymajÄcy ostatnie session_id dla danego dnia
string SessionIdFile()
{
   // per konto, per dzieĹ
   return StringFormat("session_id_%I64u_%s.txt",
                       (ulong)g_login,
                       DateStr(g_day_start));
}

// wczytaj ostatnie session_id z pliku (restart-safe)
int LoadLastSessionId()
{
   string f = SessionIdFile();
   int h = FileOpen(f, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
      return 0; // brak pliku = start dnia

   string s = FileReadString(h);
   FileClose(h);

   int v = (int)StringToInteger(s);
   return v;
}

// zapisz aktualne session_id
void SaveLastSessionId(int id)
{
   string f = SessionIdFile();
   int h = FileOpen(f, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("Cannot save session id err=", GetLastError());
      return;
   }
   FileWriteString(h, (string)id);
   FileClose(h);
}
// --- helper do lotĂłw (teĹź z przecinkiem) ---
string LotStr(double v)
{
   return NumStr(v, 2);
}

bool FileExistsCommon(const string name)
{
   int h = FileOpen(name, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h==INVALID_HANDLE) return false;
   FileClose(h);
   return true;
}
//sprawdzaj, czy nagĹĂłwek faktycznie jest w pliku
bool FileHasLineCommon(const string name, const string starts_with)
{
   int h = FileOpen(name, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE) return false;

   int sz = (int)FileSize(h);
   string content = (sz > 0 ? FileReadString(h, sz) : "");
   FileClose(h);

   return (StringFind(content, starts_with) >= 0);
}

// Tworzy nagłówek dla pliku dziennego GLOBAL:
// g_daily_file = "DailySessionSummary.csv" (wspólny plik)
void EnsureHeaderDaily()
{
   // Nagłówek globalnego pliku DailySessionSummary.csv (14 kolumn – zgodnie z .cursorrules)
   string EXPECTED_HEADER =
      "date;konto;session_id;"
      "start_balance;end_balance;"
      "max_session_equity_drawdown;max_session_profit;"
      "max_single_lot;max_total_lot;"
      "max_margin_burned;max_session_equity_burned_percent;account_reset;"
      "minute_session_start;minute_session_end";

   Print("EnsureHeaderDaily: g_daily_file = ", g_daily_file);

   // Sprawdź, czy plik już istnieje
   int h = FileOpen(g_daily_file, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h != INVALID_HANDLE)
   {
      FileClose(h);
      Print("EnsureHeaderDaily: plik ", g_daily_file, " już istnieje – nagłówek pozostawiony bez zmian.");
      return;
   }

   // Próba utworzenia nowego pliku
   int hw = FileOpen(g_daily_file, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(hw == INVALID_HANDLE)
   {
      Print("EnsureHeaderDaily: BŁĄD tworzenia pliku ", g_daily_file, " err=", GetLastError());
      return;
   }

   // Zapis nagłówka
   Print("EnsureHeaderDaily: tworzę nowy plik ", g_daily_file, " i zapisuję nagłówek.");
   FileWriteString(hw, "sep=;\r\n");
   FileWriteString(hw, EXPECTED_HEADER + "\r\n");
   FileClose(hw);
}

// Tworzy nagĹĂłwek dla plikĂłw DailySessionSummary_<konto>.csv
void EnsureHeaderDailyPerAccount(const string filename)
{
   Print("EnsureHeaderDailyPerAccount: filename=", filename);

   // jeĹli plik istnieje, ale ma rozmiar 0 â traktuj jak nowy
   int h_exist = FileOpen(filename, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h_exist != INVALID_HANDLE)
   {
      int sz = (int)FileSize(h_exist);
      FileClose(h_exist);
      if(sz > 0)
      {
         Print("EnsureHeaderDailyPerAccount: file exists and nonâempty, no header write");
         return;
      }
      // sz == 0 â kontynuujemy i nadpisujemy nagĹĂłwkiem
      Print("EnsureHeaderDailyPerAccount: file exists but empty, will write header");
   }

   int h = FileOpen(filename, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("EnsureHeaderDailyPerAccount: cannot create file ", filename,
            " err=", GetLastError());
      return;
   }

   Print("EnsureHeaderDailyPerAccount: writing header to ", filename);

   FileWriteString(h, "sep=;\r\n");

   string header =
   "date;konto;session_id;"
   "start_balance;end_balance;"
   "max_session_equity_drawdown;max_daily_loss;"
   "max_daily_profit;total_daily_profit;"
   "max_single_lot;max_total_lot;"
   "max_margin_burned;account_reset;"
   "minute_session_start;minute_session_end";

   FileWriteString(h, header + "\r\n");
   FileClose(h);
}
// Nagłówek dla plików DailySessionDeals_<konto>.csv
void EnsureHeaderDailyDealsPerAccount(const string filename)
{
   int h = FileOpen(filename, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h != INVALID_HANDLE)
   {
      FileClose(h);
      return; // plik juĹź istnieje (zakĹadamy poprawny nagĹĂłwek)
   }

   int hw = FileOpen(filename, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(hw == INVALID_HANDLE)
   {
      Print("EnsureHeaderDailyDealsPerAccount: cannot create file ", filename,
            " err=", GetLastError());
      return;
   }

   FileWriteString(hw, "sep=;\r\n");

   // Nagłówek 18 kolumn (zgodnie ze schematem: dodatkowa kolumna max_session_equity_burned_percent)
   string header =
   "date;konto;session_id;"
   "deal_time;deal_ticket;symbol;direction;volume;price;"
   "profit_only;"
   "max_session_equity_drawdown;max_session_profit;"
   "max_total_lot;"
   "max_margin_burned;max_session_equity_burned_percent;account_reset;"
   "minute_session_start;minute_session_end";

   FileWriteString(hw, header + "\r\n");
   FileClose(hw);
   
   // RESET antyâduplikacji deals-Ăłw dla nowego pliku per konto
   g_last_deal_ticket_logged   = 0;
   g_last_deal_time_msc_logged = 0;
   
   Print("EnsureHeaderDailyDealsPerAccount: NEW FILE, resetting deal cursors, filename=",
         filename, " login=", g_login);
}

// Nagłówek dla wspólnego DailySessionSummary.csv (14 kolumn – zgodnie ze schematem .cursorrules)
void EnsureHeaderDailyGlobal()
{
   string EXPECTED_HEADER =
      "date;konto;session_id;"
      "start_balance;end_balance;"
      "max_session_equity_drawdown;max_session_profit;"
      "max_single_lot;max_total_lot;"
      "max_margin_burned;max_session_equity_burned_percent;account_reset;"
      "minute_session_start;minute_session_end";

   int h = FileOpen(g_daily_global_file, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h != INVALID_HANDLE)
   {
      FileClose(h);
      return; // plik już jest
   }

   int hw = FileOpen(g_daily_global_file, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(hw == INVALID_HANDLE)
   {
      Print("Cannot create global daily summary file err=", GetLastError());
      return;
   }

   FileWriteString(hw, "sep=;\r\n");
   FileWriteString(hw, EXPECTED_HEADER + "\r\n");
   FileClose(hw);
}
void EnsureHeaderDeals() //DAILY_ACCOUNTSDETAILS.csv
{
   string EXPECTED_HEADER = "konto;date;loss;profit;lot;type;open_time;close_time";

   int h = FileOpen(InpDealsFile, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      int hw = FileOpen(InpDealsFile, FILE_WRITE | FILE_COMMON | FILE_TXT);
      if(hw==INVALID_HANDLE) { Print("Cannot create deals file err=",GetLastError()); return; }
      FileWriteString(hw, "sep=;\r\n");
      FileWriteString(hw, EXPECTED_HEADER + "\r\n");
      FileClose(hw);
      return;
   }
   FileClose(h);
}

void EnsureHeaderThresh() //SessionDD_Thresholds.csv
{
   if(FileExistsCommon(InpThreshFile)) return;

   int h = FileOpen(InpThreshFile, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(h==INVALID_HANDLE) { Print("Cannot create thresholds file err=",GetLastError()); return; }

   FileWriteString(h, "sep=;\r\n");
   FileClose(h);

   string hdr[];
   ArrayResize(hdr, 18);

   hdr[0]="date";
   hdr[1]="konto";
   hdr[2]="session_id";
   hdr[3]="minute_reached";
   hdr[4]="threshold";
   hdr[5]="session_max_dd_so_far";
   hdr[6]="margin_burned";
   hdr[7]="equity_at_time";
   hdr[8]="session_start_balance";
   hdr[9]="session_end_balance";             // << NEW
   hdr[10]="single_lot_current_max";
   hdr[11]="total_lot_current_max";
   hdr[12]="minute_session_start";
   hdr[13]="minute_session_end";
   hdr[14]="total_session_profit";
   hdr[15]="total_session_loss";
   hdr[16]="margin_call";
   hdr[17]="account_closed_stop_out";        // << NEW

   AppendRow(InpThreshFile, hdr);
}

// ---------------------------------------------------------
// AccountAgeReport.csv – nagłówek i helpery
// ---------------------------------------------------------
void EnsureHeaderAccountAge()
{
   // Sprawdź, czy plik AccountAgeReport.csv istnieje w Common\Files
   string filename = "AccountAgeReport.csv";
   if(FileIsExist(filename, FILE_COMMON))
      return;

   Print("EnsureHeaderAccountAge: file does not exist, creating with header: ", filename);

   // Utwórz nowy plik z nagłówkiem raportu Account Age
   // Używamy FILE_ANSI, żeby uniknąć problemów z rozmiarem/UTF-16 (FileSize w bajtach vs znaki)
   int h = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("EnsureHeaderAccountAge: FileOpen failed, err=", GetLastError());
      return;
   }

   // Zapisz linię określającą separator dla Excela
   FileWriteString(h, "sep=;\r\n");

   // Zapisz nagłówek (SCHEMA UPGRADE: dodano period_uid jako pierwszy klucz wiersza)
   FileWriteString(
      h,
      "period_uid;konto;account_start_date;account_end_date;session_id;"
      "account_start_balance;account_end_balance;max_equity_history;"
      "max_drawdown_pln;total_lot_current_max;account_age_days;"
      "active_trading_days;total_net_profit;max_drawdown_percent;"
      "profit_factor;total_trades;win_rate_percent;avg_trade_profit;"
      "max_consecutive_wins;max_consecutive_losses;avg_trade_duration_min;"
      "most_traded_symbol;market_session_failure;total_sessions\r\n"
   );

   FileClose(h);
   Print("EnsureHeaderAccountAge: header written OK for ", filename);
}

// Helper mapujący czas końca życia konta na sesję rynku (PL time)
string GetMarketSessionFailure(datetime end_local)
{
   // Rozbij czas lokalny na strukturę
   MqlDateTime dt;
   TimeToStruct(end_local, dt);

   int hour = dt.hour;
   int min  = dt.min;
   int tmin = hour * 60 + min; // minuty od północy

   // Definicje przedziałów sesji (PL time, minuty od północy)
   int sydney_start        = 22 * 60;        // 22:00
   int sydney_end_midnight = 24 * 60;        // 24:00 (00:00 kolejnego dnia)
   int sydney_end_morning  = 1 * 60;         // 01:00

   int tokyo_syd_start     = 1 * 60;         // 01:00
   int tokyo_syd_end       = 7 * 60;         // 07:00

   int tokyo_start         = 7 * 60;         // 07:00
   int tokyo_end           = 9 * 60 + 30;    // 09:30

   int tokyo_london_start  = 9 * 60;         // 09:00
   int tokyo_london_end    = 9 * 60 + 30;    // 09:30

   int london_start        = 9 * 60 + 30;    // 09:30
   int london_end          = 13 * 60;        // 13:00

   int overlap_start       = 13 * 60;        // 13:00
   int overlap_end         = 17 * 60 + 30;   // 17:30  (London / New York)

   int ny_start            = 17 * 60 + 30;   // 17:30
   int ny_end              = 22 * 60;        // 22:00

   // Sesja Sydney: 22:00–24:00 oraz 00:00–01:00
   if((tmin >= sydney_start && tmin < sydney_end_midnight) ||
      (tmin >= 0            && tmin < sydney_end_morning))
      return "Sydney";

   // Tokyo/Sydney: 01:00–07:00
   if(tmin >= tokyo_syd_start && tmin < tokyo_syd_end)
      return "Tokyo/Sydney";

   // Tokyo: 07:00–09:30
   if(tmin >= tokyo_start && tmin < tokyo_end)
      return "Tokyo";

   // Tokyo/London: 09:00–09:30
   if(tmin >= tokyo_london_start && tmin < tokyo_london_end)
      return "Tokyo/London";

   // London: 09:30–13:00
   if(tmin >= london_start && tmin < london_end)
      return "London";

   // London/New York overlap: 13:00–17:30
   if(tmin >= overlap_start && tmin < overlap_end)
      return "London/NewYork";

   // New York: 17:30–22:00
   if(tmin >= ny_start && tmin < ny_end)
      return "NewYork";

   return "Other";
}

// Liczy separatory ';' poza polami w cudzysłowie (RFC-style "") — wykrywa „rozjechane” wiersze DailySessionSummary.
int CountSemicolonsOutsideCsvQuotes(const string line)
{
   int n = StringLen(line);
   bool in_quotes = false;
   int cnt = 0;
   for(int i = 0; i < n; i++)
   {
      int ch = (int)StringGetCharacter(line, i);
      if(ch == '"')
      {
         // Podwójny cudzysłów wewnątrz pola cytowanego
         if(in_quotes && i + 1 < n && (int)StringGetCharacter(line, i + 1) == '"')
         {
            i++;
            continue;
         }
         in_quotes = !in_quotes;
         continue;
      }
      if(!in_quotes && ch == ';')
         cnt++;
   }
   return cnt;
}

// Czy zapis dotyczy globalnego DailySessionSummary.csv (ścisły schemat 14 kolumn wg .cursorrules).
bool IsTargetDailySessionSummaryCsv(const string name)
{
   return (name == g_daily_global_file || name == "DailySessionSummary.csv");
}

void AppendRow(const string name, const string &cols[])
{
   int sz = ArraySize(cols);

   // DEBUG: pokaż ile elementów ma tablica i co jest w pierwszych dwóch
   PrintFormat("DEBUG AppendRow: file=%s size=%d first='%s'%s",
               name,
               sz,
               (sz > 0 ? cols[0] : ""),
               (sz > 1 ? StringFormat(" second='%s'", cols[1]) : ""));

   // Zbuduj linię CSV przed FileOpen: wtedy, jeśli plik jest zablokowany,
   // możemy bezstratnie odłożyć gotowy wiersz do pending queue.
   string line = "";
   for(int i = 0; i < sz; i++)
   {
      string v = cols[i];

      // CSV escaping: jeśli jest ; albo " albo prawdziwy newline -> cytujemy
      bool need_quotes =
         (StringFind(v, ";")  >= 0) ||
         (StringFind(v, "\"") >= 0) ||
         (StringFind(v, "\n") >= 0) ||
         (StringFind(v, "\r") >= 0);

      if(need_quotes)
      {
         v = StringReplace(v, "\"", "\"\"");
         v = StringFormat("\"%s\"", v);
      }

      if(i > 0)
         line += ";";
      line += v;
   }

   // Ochrona przed „poziomym” rozjechaniem kolumn w Excelu: globalny summary = dokładnie 14 pól / 13 delimiterów poza cudzysłowami.
   if(IsTargetDailySessionSummaryCsv(name))
   {
      if(sz != 14)
      {
         Print("AppendRow: OCHRONA DailySessionSummary — wymagane cols[]=14 kolumn (schema global), podano sz=",
               sz, " — ZAPIS ANULOWANY (unikniesz setek kolumn w jednym wierszu). file=", name);
         return;
      }
      int delim_out = CountSemicolonsOutsideCsvQuotes(line);
      if(delim_out != 13)
      {
         Print("AppendRow: OCHRONA DailySessionSummary — po złożeniu linii: delimiterów ';' poza cudzysłowem=",
               delim_out, " (oczekiwano 13 dla 14 kolumn) — ZAPIS ANULOWANY. file=", name,
               " preview=", StringSubstr(line, 0, 160));
         return;
      }
   }

   // Uwaga: nadal otwieramy z FILE_COMMON, a CSV składamy sami na ';'
   int h = FileOpen(name, FILE_WRITE | FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("AppendRow: target locked/unopenable, queue row instead. name=", name, " err=", GetLastError());

      // Pending queue per docelowy plik (żeby flush był prosty).
      string qname = name + g_pending_write_suffix;
      int qh = FileOpen(qname, FILE_WRITE | FILE_READ | FILE_COMMON | FILE_TXT);
      if(qh != INVALID_HANDLE)
      {
         FileSeek(qh, 0, SEEK_END);
         FileWriteString(qh, line + "\r\n");
         FileClose(qh);
      }
      else
      {
         Print("AppendRow: ALSO failed queue open qname=", qname, " err=", GetLastError());
      }

      return;
   }

   FileSeek(h, 0, SEEK_END);

   // prawdziwy CRLF, nie sekwencje znaków '\r' '\n'
   FileWriteString(h, line + "\r\n");
   FileClose(h);
}

// ---------------- Pending queue flush ----------------
void FlushPendingWriteQueueForFile(const string target_name)
{
   string qname = target_name + g_pending_write_suffix;

   // Otwórz kolejkę do odczytu tekstowego.
   // Uwaga: czytamy linia-po-linii (nie FileReadString(..., FileSize)),
   // bo odczyt "po bajtach" potrafi wnosić NUL-e i psuć format CSV.
   int hq = FileOpen(qname, FILE_READ | FILE_COMMON | FILE_TXT);
   if(hq == INVALID_HANDLE)
      return; // brak kolejki

   string content = "";
   int q_lines = 0;
   while(!FileIsEnding(hq))
   {
      string row = FileReadString(hq);
      // Zachowaj klasyczny CRLF, spójny z AppendRow.
      content += row + "\r\n";
      q_lines++;
   }
   FileClose(hq);

   if(content == "")
   {
      FileDelete(qname);
      return;
   }

   // Spróbuj dopisać do docelowego pliku.
   int ht = FileOpen(target_name, FILE_WRITE | FILE_READ | FILE_COMMON | FILE_TXT);
   if(ht == INVALID_HANDLE)
   {
      // Jeśli nadal zablokowany - nie kasujemy kolejki.
      Print("FlushPendingWriteQueueForFile: target still locked/unopenable target=", target_name,
            " queue=", qname, " queued_lines=", q_lines, " err=", GetLastError());
      return;
   }

   FileSeek(ht, 0, SEEK_END);
   FileWriteString(ht, content);
   FileClose(ht);

   // Sukces -> usuń kolejkę.
   FileDelete(qname);
   // Log sukcesu — łatwiej potwierdzić w Experts, że pending faktycznie się opróżnił.
   Print("FlushPendingWriteQueueForFile: OK dopisano kolejkę do target=", target_name,
         " lines=", q_lines, " bytes=", (string)StringLen(content));
}

void FlushPendingWriteQueues()
{
   // Flush tylko znanych plików, które w praktyce blokują się przez Excel.
   // (Kolejka jest per docelowy plik, więc flush jest deterministyczny.)
   FlushPendingWriteQueueForFile(g_daily_file);
   // AppendDailyFinalRow zapisuje zawsze do g_daily_global_file — flush musi objąć i ten plik, jeśli nazwa różni się od InpDailyFile.
   if(g_daily_global_file != g_daily_file)
      FlushPendingWriteQueueForFile(g_daily_global_file);

   string perfile = StringFormat("DailySessionDeals%I64u.csv", g_login);
   FlushPendingWriteQueueForFile(perfile);

   FlushPendingWriteQueueForFile(InpThreshFile);
   FlushPendingWriteQueueForFile(InpDealsFile);
}
// Helper: znajdĹş czas otwarcia pozycji po position_id (minimalnie poprawnie)
datetime FindOpenTimeByPositionId(ulong pos_id, datetime from_server, datetime to_server)
{
   // szukamy DEAL_ENTRY_IN dla tego samego DEAL_POSITION_ID
   // UWAGA: dziaĹa w zakresie HistorySelect(from,to), wiÄc woĹamy to po HistorySelect().
   int total = HistoryDealsTotal();
   datetime best = 0;

   for(int i=0;i<total;i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(tk==0) continue;

      ulong pid = (ulong)HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      if(pid != pos_id) continue;

      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;

      datetime tt = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      if(tt < from_server || tt > to_server) continue;

      if(best==0 || tt < best) best = tt;
   }
   return best;
}
// Logowanie jednego dealâa do pliku (helper)
void LogDealDetail(ulong deal_ticket, datetime open_time_server, datetime close_time_server, double p)
{
   string row[8];
   ArrayResize(row, 8);

   double vol = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   long   typ = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);

   string type_str = (typ==DEAL_TYPE_BUY ? "buy" : (typ==DEAL_TYPE_SELL ? "sell" : "other"));

   double profit = (p > 0 ? p : 0.0);
   double loss   = (p < 0 ? p : 0.0);

   row[0] = (string)g_login;
   row[1] = DateStr(ToLocal(close_time_server)); // Jak chcesz âDATA transakcji jak w MT5â, to lepiej braÄ z close_time (lokalnego)
   row[2] = NumStr(loss, 2);
   row[3] = NumStr(profit, 2);
   row[4] = LotStr(vol);
   row[5] = type_str;

   // czasy: zapisujemy lokalnie (PL) Ĺźeby byĹo jak chcesz
   datetime open_local  = ToLocal(open_time_server);
   datetime close_local = ToLocal(close_time_server);

   row[6] = MinuteStr(open_local);
   row[7] = MinuteStr(close_local);

   EnsureHeaderDeals();
   AppendRow(InpDealsFile, row);
}

// ---------------------------------------------------------
// Aktualizuje (nadpisuje) wiersz dzienny w GLOBALNYM DailySessionSummary.csv
// Klucz: date + konto. Separator: ';'
// ---------------------------------------------------------
void UpsertDailyRow()
{

PrintFormat("DEBUG UpsertDailyRow ENTER: day=%s konto=%I64u sess=%d",
            DateStr(g_day_start), g_login, g_session_id);

   double end_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string date_str    = DateStr(g_day_start);   // NIGDY nie 0, zawsze g_day_start
   string konto_str   = (string)g_login;

   string resetFlag = "";
   if(g_day_failed)
      resetFlag = "FAILED";
   else if(g_day_reset)
      resetFlag = "RESET";

   // czasy sesji – zapisujemy TYLKO jeśli mamy sensowny start
   string start_str = "";
   string end_str   = "";

   if(g_session_start_time > 0)
   {
      datetime minute_session_start_local = FloorToMinuteLocal(ToLocal(g_session_start_time));
      datetime minute_session_end_local   = FloorToMinuteLocal(NowTime());

      start_str = MinuteStrLocal(minute_session_start_local);
      end_str   = MinuteStrLocal(minute_session_end_local);
   }

   // DEBUG: zanim złożysz wiersz – surowe wartości
   PrintFormat("DEBUG UpsertDailyRow: date=%s konto=%s sess_id=%d g_day_start=%I64d g_session_start_time=%I64d start_str='%s' end_str='%s'",
               date_str, konto_str, g_session_id,
               (long)g_day_start, (long)g_session_start_time,
               start_str, end_str);

   // Ten sam układ 14 kolumn co AppendDailyFinalRow (schema globalnego DailySessionSummary.csv) —
   // wcześniej jeden string z wieloma „;” trafiał jako jedna komórka albo rozjeżdżał Excel przy błędnym cytowaniu.
   double session_net = g_session_profit_pos + g_session_profit_neg;
   double burned = 0.0;
   if(g_session_start_balance > 0.0)
      burned = (MathAbs(g_session_max_dd) / g_session_start_balance) * 100.0;

   string grow[14];
   grow[0]  = date_str;
   grow[1]  = konto_str;
   grow[2]  = "'" + (string)g_session_id;
   grow[3]  = NumStr(g_start_balance_day, 2);
   grow[4]  = NumStr(end_balance, 2);
   grow[5]  = NumStr(g_session_max_dd, 2);
   grow[6]  = NumStr(session_net, 2);
   grow[7]  = "'" + LotStr(g_session_max_single_lot);
   grow[8]  = "'" + LotStr(g_session_max_total_lot);
   grow[9]  = NumStr(g_max_margin_used, 2) + "%";
   grow[10] = NumStr(burned, 2) + "%";
   grow[11] = resetFlag;
   grow[12] = start_str;
   grow[13] = end_str;

   // Nagłówek tego samego pliku co AppendDailyFinalRow (globalny COMMON).
   EnsureHeaderDailyGlobal();

   // Globalny plik summary — spójnie z AppendDailyFinalRow (nie g_daily_file z inputu).
   AppendRow(g_daily_global_file, grow);

   // DEBUG: po zapisie jednej linii
   PrintFormat("DEBUG UpsertDailyRow DONE: file=%s sess=%d",
               g_daily_global_file, g_session_id);
}
// ---------------------------------------------------------
// helper do alertĂłw
// ---------------------------------------------------------


// Notyfikacja końca sesji – format NIEZMIENNY (zgodnie z .cursorrules pkt 21)
void NotifySessionEnd(int session_id, ulong konto, datetime minute_session_end)
{
   // Debug wejścia do funkcji notyfikacji
   Print("DEBUG NotifySessionEnd ENTER session_id=", session_id,
         " konto=", konto,
         " minute_session_end=", TimeToString(minute_session_end, TIME_DATE|TIME_MINUTES));

   // Wynik netto sesji (max_session_profit)
   double session_net = g_session_profit_pos + g_session_profit_neg;

   // Maksymalny DD w PLN w sesji (max_session_equity_drawdown)
   double max_dd_pl = g_session_max_dd;

   // Maksymalny equity burned % w sesji względem start_balance (max_session_equity_burned_percent)
   double session_burned = 0.0;
   if(g_session_start_balance > 0.0)
      session_burned = (MathAbs(g_session_max_dd) / g_session_start_balance) * 100.0;

   string msg = StringFormat(
      "session end %d dla %I64u o %s | max_lot=%s | max_dd=%s | max_session_equity_burned_percent=%s%% | max_session_profit=%s",
      session_id,
      konto,
      MinuteStrLocal(minute_session_end),
      LotStr(g_session_max_total_lot),
      NumStr(max_dd_pl, 2),
      NumStr(session_burned, 2),
      NumStr(session_net, 2)
   );

   Print(msg);
   Alert(msg);
   SendNotification(msg);
}
// ---------------------------------------------------------
// KoĹcowy zapis dnia â per konto + global
// ---------------------------------------------------------

// ---------------------------------------------------------
// Zapis podsumowania sesji do globalnego pliku DailySessionSummary.csv
// ---------------------------------------------------------
void AppendDailyFinalRow()
{
   double end_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string date_str    = DateStr(g_day_start);
   string konto_str   = (string)g_login;
   string resetFlag = "";
   if(g_day_failed)
      resetFlag = "FAILED";
   else if(g_day_reset)
      resetFlag = "RESET";
   // Wynik netto bieżącej sesji
   double session_net = g_session_profit_pos + g_session_profit_neg;
   // Oblicz spalony margin (na podstawie max DD sesji)
   double burned = 0.0;
   if(g_session_start_balance > 0.0)
      burned = (MathAbs(g_session_max_dd) / g_session_start_balance) * 100.0;
   Print("AppendDailyFinalRow: konto=", konto_str,
         " date=", date_str,
         " session_id=", g_session_id,
         " pos=", g_session_profit_pos,
         " neg=", g_session_profit_neg,
         " net=", session_net,
         " burned=", burned);
   EnsureHeaderDaily();        // per‑konto (jeśli używane)
   EnsureHeaderDailyGlobal();  // nagłówek 14 kolumn dla DailySessionSummary.csv (jeśli plik nie istnieje)

   string grow[14];
   ArrayResize(grow, 14);
   grow[0]  = date_str;
   grow[1]  = konto_str;
   grow[2]  = "'" + (string)g_session_id;
   grow[3]  = NumStr(g_session_start_balance, 2);
   grow[4]  = NumStr(end_balance, 2);
   grow[5]  = NumStr(g_session_max_dd, 2);               // max_session_equity_drawdown
   grow[6]  = NumStr(session_net, 2);                    // max_session_profit
   grow[7]  = "'" + LotStr(g_session_max_single_lot);
   grow[8]  = "'" + LotStr(g_session_max_total_lot);
   grow[9]  = NumStr(g_max_margin_used, 2) + "%";        // max_margin_burned (sesyjny margin used %)
   grow[10] = NumStr(burned, 2) + "%";                   // max_session_equity_burned_percent
   grow[11] = resetFlag;

   // Czas startu i końca sesji do globalnego podsumowania
   // minute_session_start: standardowo z g_session_start_time,
   // awaryjnie z g_day_start, jeśli z jakiegoś powodu brak startu sesji.
   // minute_session_start: standardowo z g_session_start_time,
   // awaryjnie z g_day_start, jeśli z jakiegoś powodu brak startu sesji.
   datetime start_local = ToLocal(g_session_start_time > 0 ? g_session_start_time : g_day_start);
   // minute_session_end:
   // - normalnie: g_session_end_time ustawione w EndSessionFinalize (konto FLAT),
   // - awaryjnie: jeśli brak g_session_end_time, użyj bieżącego czasu (TimeCurrent),
   //   ale poprawne wywołanie AppendDailyFinalRow powinno następować po EndSessionFinalize.
   // minute_session_end:
   // - normalnie: g_session_end_time ustawione w EndSessionFinalize (konto FLAT),
   // - awaryjnie: jeśli brak g_session_end_time, użyj bieżącego czasu (TimeCurrent),
   //   ale poprawne wywołanie AppendDailyFinalRow powinno następować po EndSessionFinalize.
   // minute_session_end:
   // - normalnie: g_session_end_time ustawione w EndSessionFinalize (konto FLAT),
   // - awaryjnie: jeśli brak g_session_end_time, użyj bieżącego czasu (TimeCurrent),
   //   ale poprawne wywołanie AppendDailyFinalRow powinno następować po EndSessionFinalize.
   // minute_session_end:
   // - normalnie: g_session_end_time ustawione w EndSessionFinalize (konto FLAT),
   // - awaryjnie: jeśli brak g_session_end_time, użyj bieżącego czasu (TimeCurrent),
   //   ale poprawne wywołanie AppendDailyFinalRow powinno następować po EndSessionFinalize.
   datetime end_local;
   if(g_session_end_time > 0)
      end_local = ToLocal(g_session_end_time);
   else
      end_local = ToLocal(TimeCurrent());
   grow[12] = MinuteStrLocal(FloorToMinuteLocal(start_local)); // minute_session_start
   grow[13] = MinuteStrLocal(FloorToMinuteLocal(end_local));   // minute_session_end

   AppendRow(g_daily_global_file, grow);
}
   
void HandleBalanceReset(datetime reset_server_time, const string reset_comment)
{
   // 1) Zapisz finalny wiersz âprzed resetemâ
   g_day_had_balance_reset      = true;
   g_last_balance_reset_time    = reset_server_time;
   g_last_balance_reset_comment = reset_comment;

   // tutaj wstawiamy FAILED dla zamykanego segmentu
   g_day_failed = true;

   // Diagnostyka: potwierdź, że reset wszedł w core flow
   Print("HandleBalanceReset: ENTER konto=", (string)g_login,
         " reset_time=", TimeToString(ToLocal(reset_server_time), TIME_DATE|TIME_MINUTES),
         " comment=", reset_comment,
         " bal_now=", NumStr(AccountInfoDouble(ACCOUNT_BALANCE), 2),
         " eq_now=",  NumStr(AccountInfoDouble(ACCOUNT_EQUITY), 2));

   AppendDailyFinalRow();           // zapis segmentu z FAILED

   // 2) Restart liczenia âw tym samym dniuâ od nowej bazy
   // Uwaga: NIE zmieniamy g_day_start (bo to wciÄĹź ta sama data)
   g_start_balance_day   = AccountInfoDouble(ACCOUNT_BALANCE);

   g_day_max_dd          = 0.0;
   g_day_max_profit      = 0.0;
   g_day_min_profit      = 0.0;
   g_day_total_profit    = 0.0;
   g_day_loss_sum        = 0.0;
   g_day_profit_sum      = 0.0;

   g_day_max_single_lot  = 0.0;
   g_day_max_total_lot   = 0.0;

   g_day_max_margin_burned = 0.0;
   g_day_failed            = false; // po resecie nowy segment dnia, bez FAILED

   // restart sesji tracking (Ĺźeby sesje po resecie byĹy czyste)
   g_session_active   = false;
   g_bucket_minute    = 0;
   g_bucket_profit    = 0.0;
   g_bucket_has_close = false;

   // kursor historii: przesuĹ, Ĺźeby nie wykrywaÄ resetu drugi raz
   g_last_deal_time   = reset_server_time;
   g_last_deal_ticket = 0;

   // ------------------------------------------------------
   // Account Age Report – start nowego okresu życia konta
   // ------------------------------------------------------
   g_account_start_time    = reset_server_time;                   // zapisz czas resetu jako początek okresu
   // Utwórz nowy unikalny ID okresu życia (RESET otwiera nowy cykl update)
   // Format: login_<server_seconds> (twardy, deterministyczny, odporny na formatowanie Excela)
   g_account_period_uid    = (string)g_login + "_" + (string)((long)g_account_start_time);
   g_account_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);  // saldo po resecie jako nowa baza
   g_account_max_equity    = g_account_start_balance;             // na starcie equity == balance
   g_session_end_time      = 0;                                   // żeby BuildAccountAgeLine dał end_date = start (brak sesji w nowym okresie)

   // Wyzeruj liczniki raportu Account Age dla nowego okresu
   g_active_trading_days        = 0;
   g_last_trade_day             = 0;
   g_total_trades               = 0;
   g_win_trades                 = 0;
   g_sum_profit                 = 0.0;
   g_sum_loss                   = 0.0;
   g_consecutive_wins           = 0;
   g_max_consecutive_wins       = 0;
   g_consecutive_losses         = 0;
   g_max_consecutive_losses     = 0;
   g_total_trade_duration_sec   = 0.0;
   g_total_sessions             = 0;
   g_account_age_reported       = false;

   Print("AccountAgeReport: new life period started at reset_time=",
         TimeToString(ToLocal(reset_server_time), TIME_DATE | TIME_MINUTES),
         " start_balance=", g_account_start_balance);

   // Utwórz nowy wiersz w AccountAgeReport.csv (od tego momentu konto „żyje” w raporcie)
   UpsertAccountAgeRow();

   // Diagnostyka: pokaż nowy UID okresu życia konta po resecie
   Print("HandleBalanceReset: EXIT konto=", (string)g_login,
         " new_period_uid=", g_account_period_uid,
         " start_time_server=", TimeToString(g_account_start_time, TIME_DATE|TIME_MINUTES),
         " start_balance=", NumStr(g_account_start_balance, 2));
}

// -------------------- filtering hel --------------------
bool PassPositionFiltersByIndex(const int idx) // przepuszcza tylko pozycje o symbolu równym symbolowi wykresu. Jeśli na koncie są pozycje na innych symbolach, nie będą one liczone do open_cnt To może powodować przedwczesne kończenie sesji (gdy wszystkie pozycje na bieżącym symbolu zostaną zamknięte, ale na innych symbolach są jeszcze otwarte). Jeśli chcesz śledzić wszystkie pozycje na koncie, usuń filtr symbolu lub dostosuj go do swoich potrzeb.
{
   ulong ticket = PositionGetTicket(idx);
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;

   // bierzemy tylko pozycje z tego samego symbolu co wykres z EA
   string chart_symbol = _Symbol;
   string pos_symbol   = PositionGetString(POSITION_SYMBOL);
   if(pos_symbol != chart_symbol)
      return false;

   // opcjonalnie: jeĹli kiedyĹ chcesz filtrowaÄ po magicu,
   // moĹźesz tu dopisaÄ warunek, ale na razie pomijamy.
   return true;
}
int CountFilteredPositions(double &total_volume, double &max_single_volume)
{
   total_volume = 0.0;
   max_single_volume = 0.0;

   int total = PositionsTotal();
   int cnt=0;
   for(int i=0;i<total;i++)
   {
      if(!PassPositionFiltersByIndex(i)) continue;
      cnt++;
      double vol = PositionGetDouble(POSITION_VOLUME);
      total_volume += vol;
      if(vol > max_single_volume) max_single_volume = vol;
   }
   return cnt;
}
bool IsTradeDeal(ulong deal_ticket)
{
   long type = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
   return (type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL);
}
bool PassDealFilters(ulong deal_ticket)
{
   if(InpSymbolFilter!="" && HistoryDealGetString(deal_ticket, DEAL_SYMBOL)!=InpSymbolFilter)
      return false;
   if(InpMagicFilter!=-1 && (long)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC)!=InpMagicFilter)
      return false;
   return true;
}

double DealProfitOnly(ulong deal_ticket)
{
   return HistoryDealGetDouble(deal_ticket, DEAL_PROFIT); // PROFIT ONLY
}


// ---------------------------------------------------------
// Deal logger per konto: jeden wiersz = jedna transakcja
// Plik: DailySessionDeals<konto>.csv
// ---------------------------------------------------------
void LogDealPerAccount(ulong dealticket, int sessionid, double sessiontotalprofit)
{
   string kontostr = (string)g_login;
   string perfile  = StringFormat("DailySessionDeals%I64u.csv", (ulong)g_login);

   EnsureHeaderDailyDealsPerAccount(perfile);

   datetime dealtime   = (datetime)HistoryDealGetInteger(dealticket, DEAL_TIME);
   string   symbol     = HistoryDealGetString(dealticket, DEAL_SYMBOL);
   long     type       = HistoryDealGetInteger(dealticket, DEAL_TYPE);
   double   volume     = HistoryDealGetDouble(dealticket, DEAL_VOLUME);
   double   price      = HistoryDealGetDouble(dealticket, DEAL_PRICE);
   double   profitonly = HistoryDealGetDouble(dealticket, DEAL_PROFIT);

   string dir = "";
   if(type == DEAL_TYPE_BUY)  dir = "buy";
   if(type == DEAL_TYPE_SELL) dir = "sell";

   // DEBUG podstawowy
   PrintFormat("LogDealPerAccount login=%I64u sessionid=%d ticket=%I64u time=%s symbol=%s volume=%.2f profit=%.2f",
               g_login,
               sessionid,
               dealticket,
               MinuteStrLocal(ToLocal(dealtime)),
               symbol,
               volume,
               profitonly);

   // --- Czas rozpoczęcia sesji (lokalny) ---
   datetime minutesessionstartlocal;
   if(g_session_start_time == 0)
   {
      // Awaryjnie: użyj czasu pierwszego deala w tej sesji
      minutesessionstartlocal = FloorToMinuteLocal(ToLocal(dealtime));
      PrintFormat("WARN: g_session_start_time==0, fallback to dealtime %s for minutesessionstart",
                  TimeToString(dealtime, TIME_DATE|TIME_MINUTES));
   }
   else
   {
      minutesessionstartlocal = FloorToMinuteLocal(ToLocal(g_session_start_time));
   }
   // --- Czas zakończenia sesji (lokalny) ---
   // Priorytet:
   // 1) jeśli g_session_end_time ustawione w EndSessionFinalize (konto FLAT) – użyj go,
   // 2) w przeciwnym razie użyj minuty bieżącego deala (ostatni znany close).
   datetime minutesessionendlocal;
   string end_source = "";
   if(g_session_end_time > 0)
   {
      minutesessionendlocal = FloorToMinuteLocal(ToLocal(g_session_end_time));
      end_source = "SESSION_END";
   }
   else
   {
      minutesessionendlocal = FloorToMinuteLocal(ToLocal(dealtime));
      end_source = "DEAL_TIME";
   }
   Print("LogDealPerAccount: ticket=", dealticket,
         " g_session_end_time=", TimeToString(g_session_end_time),
         " end_source=", end_source,
         " end_local=", MinuteStrLocal(minutesessionendlocal));
   string resetFlag = "";
   if(g_day_failed)
      resetFlag = "FAILED";
   else if(g_day_reset)
      resetFlag = "RESET";

   double sessionnet = sessiontotalprofit;

   // Spalony equity w sesji (max_session_equity_burned_percent) – DD% względem start_balance
   double session_burned = 0.0;
   if(g_session_start_balance > 0.0)
      session_burned = (MathAbs(g_session_max_dd) / g_session_start_balance) * 100.0;

   // DEBUG o sesji – pełen podgląd
   PrintFormat("LogDealPerAccount login=%I64u sess=%d ticket=%I64u dealTime=%s sessNet=%.2f start=%s end=%s burned=%.2f%% margin_used_max=%.2f%%",
               g_login, sessionid, dealticket,
               MinuteStrLocal(ToLocal(dealtime)),
               sessionnet,
               MinuteStrLocal(minutesessionstartlocal),
               MinuteStrLocal(minutesessionendlocal),
               session_burned,
               g_max_margin_used);

   // --- Składanie wiersza (18 kolumn – zgodnie ze schematem) ---
   string row[18];
   ArrayResize(row, 18);
   int i = 0;

   row[i++] = DateStr(g_day_start);               // date
   row[i++] = kontostr;                           // konto
   row[i++] = (string)sessionid;                  // session_id

   row[i++] = MinuteStrLocal(ToLocal(dealtime));  // deal_time
   row[i++] = (string)dealticket;                 // deal_ticket
   row[i++] = symbol;                             // symbol
   row[i++] = dir;                                // direction
   row[i++] = LotStr(volume);                     // volume
   row[i++] = NumStr(price, 2);                   // price

   row[i++] = NumStr(profitonly, 2);              // profit_only

   row[i++] = NumStr(g_session_max_dd, 2);        // max_session_equity_drawdown
   row[i++] = NumStr(sessionnet, 2);              // max_session_profit (TOTAL sesji)

   row[i++] = LotStr(g_session_max_total_lot);    // max_total_lot
   row[i++] = NumStr(g_max_margin_used, 2);       // max_margin_burned (sesyjny margin used %)
   row[i++] = NumStr(session_burned, 2) + "%";    // max_session_equity_burned_percent

   row[i++] = resetFlag;                          // account_reset

   row[i++] = MinuteStrLocal(minutesessionstartlocal); // minute_session_start
   row[i++] = MinuteStrLocal(minutesessionendlocal);   // minute_session_end

   AppendRow(perfile, row);
}
// -------------------- day stats --------------------
datetime g_day_start=0;
double   g_start_balance_day=0.0;

double   g_day_max_dd=0.0;          // most negative ajbardziej ujemny equity drawdown z caĹego dnia
double   g_day_max_profit=0.0;      // (moĹźesz zostawiÄ, ale nie uĹźyjemy w daily)
double   g_day_min_profit=0.0;      // most negative (max loss)
double   g_day_total_profit=0.0;    // NET daily profit (to zostaje w daily)
double   g_day_loss_sum = 0.0;      // << DODANE
double   g_day_profit_sum = 0.0;    // << DODANE

double   g_day_max_single_lot=0.0;
double   g_day_max_total_lot=0.0;

// NEW:
double   g_day_max_margin_burned=0.0; // max burned% z dnia
bool     g_day_reset  = false;
bool     g_day_failed=false;          // FAILED jeĹli stopout lub balance/equity < 1000

bool     g_day_had_balance_reset = false;
datetime g_last_balance_reset_time = 0;
string   g_last_balance_reset_comment = "";

ulong    g_login=0;

// -------------------- GLOBALS session stats --------------------
bool     g_session_active=false;
int      g_session_id=0;

double   g_session_start_equity=0.0;
datetime g_session_start_time=0;
datetime g_session_end_time=0;      // << TU

double   g_session_max_dd=0.0;      // most negative (Equity - session_start_equity)
double   g_session_max_single_lot=0.0;
double   g_session_max_total_lot=0.0;

double   g_next_dd_threshold=0.0;   // e.g. -1000, -2000...
double   g_session_start_balance = 0.0;

double   g_session_end_balance   = 0.0;   // << NEW: end balance sesji
bool     g_session_closed_so     = false; // << NEW: czy sesja zamkniÄta przez stop-out

// --- session profit/loss totals (sum z caĹej sesji, obejmuje czÄĹciowe zamkniÄcia) ---
double   g_session_profit_pos = 0.0;  // suma dodatnich DEAL_PROFIT w sesji
double   g_session_profit_neg = 0.0;  // suma ujemnych DEAL_PROFIT w sesji

// --- margin call / stopout tracking ---
bool     g_seen_margin_call = false;
bool     g_seen_stop_out    = false;
double   g_min_margin_level = 999999.0;   // minimalny margin level % w sesji
double   g_max_margin_used  = 0.0;        // max (margin/equity*100) w sesji
double   g_worst_floating_pl= 0.0;        // najbardziej ujemny floating P/L w sesji (z pozycji)
string   g_margin_comment   = "";         // tekst do kolumny margin_call
double   g_margin_alert_level = 0.0;   // najwyĹźszy prĂłg alertu juĹź wysĹany

// NOWE ZMIENNE – alerty  drawdown &  Margin Level
double   g_dd_alert_sent = 0; // Poziom ostatniego wysłanego alertu drawdown (20,40,60)
double   g_margin_level_alert_sent = 0; // Poziom ostatniego wysłanego alertu Margin Level (80,50,20)
// Alerty sumy wolumenu otwartych pozycji w sesji (max total lot) — progi 50 / 100 / 150 / 200
double   g_total_lot_alert_sent = 0; // Ostatnio „zaliczony” próg (50, 100, 150, 200)
bool     g_is_live_account = false;  // Konto LIVE (produkcja) -> alerty co 10 lot

bool IsLiveProductionAccount(const ulong login, const string server)
{
   string srv = server;
   StringToLower(srv);
   if(StringFind(srv, "live") >= 0)
      return true;

   // Konta LIVE z docs/trading_accounts_mt5.md (+ historyczne warianty loginów do zgodności).
   if(login == 10849931 || login == 11711840 || login == 11710937 || login == 11711937 ||
      login == 18495775 || login == 18435775 || login == 18495776 || login == 18495777)
      return true;

   return false;
}

// -------------------- Account Age Report globals --------------------
// Dane jednego okresu życia konta (od resetu do FAIL/stop-out)
string   g_account_period_uid        = "";    // unikalny ID okresu życia (RESET otwiera, FAIL zamyka cykl update)
double   g_account_start_balance      = 0.0;   // saldo na starcie okresu życia konta
datetime g_account_start_time         = 0;     // czas startu okresu życia konta (server)
double   g_account_max_equity         = 0.0;   // maksymalne equity w całym okresie

int      g_active_trading_days        = 0;     // licznik dni z handlem w okresie
datetime g_last_trade_day             = 0;     // ostatni dzień z transakcją (DayStartLocal)

int      g_total_trades               = 0;     // liczba wszystkich transakcji w okresie
int      g_win_trades                 = 0;     // liczba transakcji zakończonych zyskiem
double   g_sum_profit                 = 0.0;   // suma profit_only > 0 z całego okresu
double   g_sum_loss                   = 0.0;   // suma |profit_only| dla strat z całego okresu

int      g_consecutive_wins           = 0;     // bieżąca seria wygranych
int      g_max_consecutive_wins       = 0;     // maksymalna seria wygranych
int      g_consecutive_losses         = 0;     // bieżąca seria strat
int      g_max_consecutive_losses     = 0;     // maksymalna seria strat

double   g_total_trade_duration_sec   = 0.0;   // łączny czas trwania transakcji (sekundy)

int      g_total_sessions             = 0;     // liczba zakończonych sesji w okresie życia konta
bool     g_account_age_reported       = false; // czy końcowy wiersz okresu został zapisany

// -------------------- close-minute bucket --------------------
datetime g_bucket_minute=0;
double   g_bucket_profit=0.0;
bool     g_bucket_has_close=false;

// deal cursor
datetime g_last_deal_time=0;
ulong    g_last_deal_ticket=0;

// -------------------- session controls --------------------
void StartSession()
{
   if(g_session_active)
      return;

   g_session_active          = true;
   g_session_start_time = TimeCurrent(); // server time
   g_session_start_balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_session_start_equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_session_end_balance     = g_session_start_balance;

   g_session_profit_pos      = 0.0;
   g_session_profit_neg      = 0.0;
   g_session_max_dd          = 0.0;
   g_session_max_single_lot  = 0.0;
   g_session_max_total_lot   = 0.0;
   g_worst_floating_pl       = 0.0;
   g_seen_stop_out           = false;
   g_seen_margin_call        = false;
   g_margin_comment          = "";

   // nowy session_id z pliku helpera (restart-safe)
   int last_id   = LoadLastSessionId();
   g_session_id  = last_id + 1;
   SaveLastSessionId(g_session_id);
   
   // Resetuj progi alertów na nową sesję
   g_dd_alert_sent = 0;
   g_margin_level_alert_sent = 0;
   g_total_lot_alert_sent = 0;

   // na starcie nowej sesji resetujemy dzienne flagi FAIL tylko przy resecie
   // (g_day_failed zostaje true, jeĹli juĹź byĹ stop-out / <1000 w tym dniu)
   // przy klasycznym resecie MT5 moĹźesz ustawiÄ g_day_reset=true w logice resetu
   // tutaj tylko czyĹcimy komentarz do resetu
   g_last_balance_reset_comment = "";
}

// ---------------------------------------------------------
// Kończenie sesji – zapis podsumowania i aktualizacja statystyk dziennych
// ---------------------------------------------------------
void EndSessionFinalize()
{
   if(!g_session_active)
      return;   // blokada jako pierwsza linia

   Print("DEBUG EndSessionFinalize ENTER session_id=", g_session_id,
         " login=", g_login);

   // Ustaw koniec sesji (czas serwerowy)
   g_session_end_time = TimeCurrent();

   if(g_session_start_time == 0)
      g_session_start_time = g_day_start;   // fallback: początek dnia

   // Finalizacja ostatniego bucketa (jeśli istnieje i jesteśmy FLAT)
   if(g_bucket_has_close)
   {
      double p = g_bucket_profit;

      // NIE doliczamy do g_day_total_profit tutaj,
      // aby nie dublować względem deal totals
      if(p > g_day_max_profit) g_day_max_profit = p;
      if(p < g_day_min_profit) g_day_min_profit = p;
   }

   // --- Wynik netto sesji ---
   double session_net = g_session_profit_pos + g_session_profit_neg;

   // Aktualizacja dziennych maksimów na podstawie sesji
   if(session_net > g_day_max_profit)
      g_day_max_profit = session_net;

   g_day_total_profit += session_net;

   if(g_session_max_dd         < g_day_max_dd)         g_day_max_dd         = g_session_max_dd;
   if(g_session_max_single_lot > g_day_max_single_lot) g_day_max_single_lot = g_session_max_single_lot;
   if(g_session_max_total_lot  > g_day_max_total_lot)  g_day_max_total_lot  = g_session_max_total_lot;

   // --- Zapis wiersza kończącego sesję w pliku progów (SessionDD_Thresholds.csv) ---
   datetime end_min = FloorToMinute(g_session_end_time);
   double   eq_now  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_session_end_balance = AccountInfoDouble(ACCOUNT_BALANCE);

   string row[];
   ArrayResize(row, 18);

   row[0]  = DateStr(g_day_start);
   row[1]  = (string)g_login;
   row[2]  = (string)g_session_id;
   row[3]  = MinuteStr(end_min);
   row[4]  = "SESSION_END";
   row[5]  = NumStr(g_session_max_dd, 2);

   double burned = 0.0;
   if(g_session_start_balance > 0.0)
      burned = (MathAbs(g_session_max_dd) / g_session_start_balance) * 100.0;

   row[6]  = NumStr(burned, 2) + "%";
   row[7]  = "'" + NumStr(eq_now, 2);
   row[8]  = NumStr(g_session_start_balance, 2);
   row[9]  = NumStr(g_session_end_balance, 2);

   row[10] = LotStr(g_session_max_single_lot);
   row[11] = LotStr(g_session_max_total_lot);

   row[12] = MinuteStr(FloorToMinute(g_session_start_time));
   row[13] = MinuteStr(end_min);
   row[14] = NumStr(g_session_profit_pos, 2);
   row[15] = NumStr(g_session_profit_neg, 2);
   row[16] = g_margin_comment;
   row[17] = (g_session_closed_so ? "ACCOUNT_CLOSED_STOP_OUT" : "");

   AppendRow(InpThreshFile, row);

   // DEBUG przed zapisem podsumowania
   Print("DEBUG EndSessionFinalize BEFORE AppendDailyFinalRow: session_id=",
         g_session_id, " login=", g_login,
         " start_balance=", g_session_start_balance,
         " end_balance=", g_session_end_balance);

   Print("DEBUG EndSessionFinalize: pos=", g_session_profit_pos, " neg=", g_session_profit_neg);

   // --- Zapis podsumowania sesji do pliku globalnego ---
   AppendDailyFinalRow();

   Print("DEBUG EndSessionFinalize AFTER AppendDailyFinalRow: session_id=",
         g_session_id, " login=", g_login);

   // ------------------------------------------------------
   // Account Age Report – aktualizacja wiersza po każdej zakończonej sesji; zamrożenie przy FAIL
   // ------------------------------------------------------
   if(!g_account_age_reported)
   {
      UpsertAccountAgeRow();   // tworzy wiersz (jeśli jeszcze nie ma) lub nadpisuje aktualnymi 23 polami
      if(g_day_failed)
      {
         // Koniec okresu życia w raporcie — usuń sidecar, żeby kolejny start EA nie „wskrzeszał” tego UID
         g_account_age_reported = true;
         ClearAccountAgeSidecar(g_login);
      }
   }

   // Powiadomienie o zakończeniu sesji
   NotifySessionEnd(g_session_id, g_login, FloorToMinuteLocal(g_session_end_time));

   // Resetuj czas zakończenia, aby nie kolidował z następną sesją
   g_session_end_time = 0;

   // Deaktywuj sesję
   g_session_active = false;
}
void ResetDay(datetime new_day_start)
{
   g_day_start = new_day_start;
   g_start_balance_day = AccountInfoDouble(ACCOUNT_BALANCE);

   g_day_max_dd = 0.0;
   g_day_max_profit = 0.0;
   g_day_min_profit = 0.0;
   g_day_total_profit = 0.0;
   g_day_loss_sum = 0.0;     // << DODANE
   g_day_profit_sum = 0.0;   // << DODANE

   g_day_max_single_lot = 0.0;
   g_day_max_total_lot  = 0.0;
   
   //NEW:
   g_day_max_margin_burned = 0.0;
   g_day_failed            = false;
   g_margin_alert_level    = 0.0;    // reset progĂłw alertu na nowy dzieĹ

   g_session_active = false;
   // reset dzienny session_id (ale restart-safe)
   g_session_id = LoadLastSessionId();

   g_bucket_minute = 0;
   g_bucket_profit = 0.0;
   g_bucket_has_close = false;

   g_last_deal_time = g_day_start;
   g_last_deal_ticket = 0;
   
    // reset anti-duplicate log for DAILY_ACCOUNTSDETAILS
   g_last_deal_ticket_logged      = 0;
   g_last_deal_time_msc_logged    = 0;
   
}

void WriteDailyRow()
{
   double end_balance = AccountInfoDouble(ACCOUNT_BALANCE);

   string row[];
   ArrayResize(row, 10);

   row[0] = DateStr(g_day_start);
   row[1] = (string)g_login;
   row[2] = NumStr(g_start_balance_day, 2);  // zamiast DoubleToString
   row[3] = NumStr(end_balance, 2);
   row[4] = NumStr(g_day_max_dd, 2);
   row[5] = NumStr(g_day_min_profit, 2);
   row[6] = NumStr(g_day_max_profit, 2);
   row[7] = NumStr(g_day_total_profit, 2);
   row[8] = LotStr(g_day_max_single_lot);    // juĹź ok
   row[9] = LotStr(g_day_max_total_lot);     // juĹź ok

   AppendRow(g_daily_file, row);
}

// -------------------- threshold logging --------------------
void LogThreshold(datetime when_minute, double threshold, double equity_now)
{

   if(g_session_start_time == 0)
   g_session_start_time = TimeCurrent(); // awaryjnie
   
   double dd_now = equity_now - g_session_start_equity;
   if(dd_now < g_session_max_dd)
      g_session_max_dd = dd_now;

   double burned = 0.0;
   if(g_session_start_balance > 0.0)
      burned = (MathAbs(g_session_max_dd) / g_session_start_balance) * 100.0;

   if(burned > g_day_max_margin_burned)
      g_day_max_margin_burned = burned;

   string row[];
   ArrayResize(row, 18);

   row[0]  = DateStr(g_day_start);
   row[1]  = (string)g_login;
   row[2]  = (string)g_session_id;
   row[3]  = MinuteStr(when_minute);
   row[4]  = NumStr(threshold, 2);
   row[5]  = NumStr(g_session_max_dd, 2);
   row[6]  = NumStr(burned, 2) + "%";
   row[7]  = "'" + NumStr(equity_now, 2);   // equity_at_time jako tekst
   row[8]  = NumStr(g_session_start_balance, 2);
   row[9]  = ""; // session_end_balance unknown until end

   row[10] = LotStr(g_session_max_single_lot);
   row[11] = LotStr(g_session_max_total_lot);

   row[12] = MinuteStr(FloorToMinute(g_session_start_time));
   row[13] = ""; // minute_session_end unknown here
   row[14] = NumStr(g_session_profit_pos, 2);
   row[15] = NumStr(g_session_profit_neg, 2);
   row[16] = g_margin_comment;

   row[17] = (g_session_closed_so ? "ACCOUNT_CLOSED_STOP_OUT" : ""); // << NEW

   AppendRow(InpThreshFile, row);
}

// ---------------------------------------------------------
// Account Age Report – budowa jednej linii CSV (23 kolumny) z aktualnych globali
// Używane przez UpsertAccountAgeRow (reset + każda zakończona sesja) i przy zamrożeniu wiersza
// ---------------------------------------------------------
string BuildAccountAgeLine()
{
   // Daty w czasie lokalnym; przy braku końca sesji używamy startu (wiersz „żyjący”)
   datetime start_local = ToLocal(g_account_start_time);
   datetime end_local   = (g_session_end_time > 0)
                          ? ToLocal(g_session_end_time)
                          : start_local;

   // Wiek konta w dniach
   int age_days = 0;
   if(g_account_start_time > 0)
   {
      datetime end_serwer = (g_session_end_time > 0) ? g_session_end_time : TimeCurrent();
      age_days = (int)((end_serwer - g_account_start_time) / (60 * 60 * 24));
   }

   double account_end_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double total_net_profit    = account_end_balance - g_account_start_balance;

   double max_dd_pln     = g_session_max_dd;
   double max_dd_percent = 0.0;
   if(g_account_start_balance > 0.0)
      max_dd_percent = (MathAbs(g_session_max_dd) / g_account_start_balance) * 100.0;

   double profit_factor = 0.0;
   if(g_sum_loss > 0.0)
      profit_factor = g_sum_profit / g_sum_loss;
   else if(g_sum_profit > 0.0)
      profit_factor = 999.99;

   double win_rate = 0.0;
   if(g_total_trades > 0)
      win_rate = (double)g_win_trades * 100.0 / (double)g_total_trades;

   double avg_trade_profit = 0.0;
   if(g_total_trades > 0)
      avg_trade_profit = total_net_profit / (double)g_total_trades;

   double avg_trade_duration_min = 0.0;
   if(g_total_trades > 0)
      avg_trade_duration_min = g_total_trade_duration_sec / 60.0 / (double)g_total_trades;

   string most_traded_symbol   = "";
   string market_session_failure = GetMarketSessionFailure(end_local);

   // Składanie linii w kolejności kolumn (SCHEMA UPGRADE: dodano period_uid jako pierwszą kolumnę)
   // session_id: 0 gdy jeszcze żadna sesja nie zakończyła się w tym okresie życia
   int sid = (g_session_end_time > 0) ? g_session_id : 0;
   string line = "";
   // period_uid: twardy klucz rekordu (UPDATE zawsze w ramach tego ID)
   string uid = g_account_period_uid;
   if(uid == "" && g_account_start_time > 0)
      uid = (string)g_login + "_" + (string)g_account_start_time;
   line += uid + ";";
   line += (string)g_login + ";";
   line += TimeToString(start_local, TIME_DATE | TIME_MINUTES) + ";";
   line += TimeToString(end_local,   TIME_DATE | TIME_MINUTES) + ";";
   line += (string)sid + ";";
   line += NumStr(g_account_start_balance, 2) + ";";
   line += NumStr(account_end_balance,      2) + ";";
   line += NumStr(g_account_max_equity, 2) + ";";
   line += NumStr(max_dd_pln, 2) + ";";
   line += LotStr(g_session_max_total_lot) + ";";
   line += (string)age_days + ";";
   line += (string)g_active_trading_days + ";";
   line += NumStr(total_net_profit, 2) + ";";
   line += NumStr(max_dd_percent, 2) + "%;";
   line += NumStr(profit_factor, 2) + ";";
   line += (string)g_total_trades + ";";
   // win_rate_percent: zapis w % jako tekst (np. 66.67%) – zgodnie z oczekiwaniem użytkownika
   line += NumStr(win_rate, 2) + "%;";
   line += NumStr(avg_trade_profit, 2) + ";";
   line += (string)g_max_consecutive_wins   + ";";
   line += (string)g_max_consecutive_losses + ";";
   line += NumStr(avg_trade_duration_min, 2) + ";";
   line += most_traded_symbol + ";";
   line += market_session_failure + ";";
   line += (string)g_total_sessions;

   return line;
}

// ---------------------------------------------------------
// Account Age — plik stanu w Common\Files (per login), żeby po restarcie EA / przeładowaniu
// nie tworzyć nowego period_uid ani nie dopisywać kolejnego wiersza do AccountAgeReport.csv.
// Przyczyna wielu „zamrożonych” wierszy: OnInit ustawiał g_account_start_time=TimeCurrent() przy
// każdym starcie (globalne MQL5 zerują się), więc Upsert nie znajdował UID w pliku → APPEND.
// Reconcile / PENDING_WRITE nie dotykają tej ścieżki.
// ---------------------------------------------------------
string AccountAgeSidecarFilename(const ulong login)
{
   return StringFormat("AccountAgeActive_%I64u.state", login);
}

void ClearAccountAgeSidecar(const ulong login)
{
   string fn = AccountAgeSidecarFilename(login);
   if(FileExistsCommon(fn))
      FileDelete(fn, FILE_COMMON);
}

// Parsuje liczby z CSV/Excel (przecinek dziesiętny, opcjonalne %)
double ParseFlexibleDouble(const string s_raw)
{
   string s = s_raw;
   StringTrimLeft(s);
   StringTrimRight(s);
   StringReplace(s, "%", "");
   StringReplace(s, " ", "");
   StringReplace(s, ",", ".");
   return StringToDouble(s);
}

bool NormalizeAccountAgeUidField(string &u)
{
   StringTrimLeft(u);
   StringTrimRight(u);
   if(StringLen(u) > 0 && (ushort)StringGetCharacter(u, 0) == 0xFEFF)
      u = StringSubstr(u, 1);
   return (StringLen(u) > 0);
}

bool LoadAccountAgeSidecar(const ulong login)
{
   string fn = AccountAgeSidecarFilename(login);
   if(!FileExistsCommon(fn))
      return false;
   int h = FileOpen(fn, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   string uid = FileReadString(h);
   string tsec = FileReadString(h);
   string sbal = FileReadString(h);
   FileClose(h);
   StringTrimLeft(uid);
   StringTrimRight(uid);
   StringTrimLeft(tsec);
   StringTrimRight(tsec);
   StringTrimLeft(sbal);
   StringTrimRight(sbal);
   if(StringLen(uid) < 3 || StringLen(tsec) < 1)
      return false;
   string prefix = (string)login + "_";
   if(StringFind(uid, prefix) != 0)
   {
      Print("LoadAccountAgeSidecar: uid nie pasuje do login — czyszczę plik fn=", fn);
      ClearAccountAgeSidecar(login);
      return false;
   }
   long sec = (long)StringToInteger(tsec);
   if(sec <= 0)
      return false;
   g_account_period_uid    = uid;
   g_account_start_time    = (datetime)sec;
   g_account_start_balance = ParseFlexibleDouble(sbal);
   if(g_account_start_balance <= 0.0)
      g_account_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return true;
}

void SaveAccountAgeSidecar()
{
   // Tylko „żywy” okres — po FAIL usuwamy sidecar (Clear), żeby kolejny start EA mógł otworzyć nowy cykl
   if(g_account_age_reported || g_account_period_uid == "" || g_account_start_time == 0)
      return;
   string fn = AccountAgeSidecarFilename(g_login);
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("SaveAccountAgeSidecar: FileOpen failed err=", GetLastError(), " fn=", fn);
      return;
   }
   FileWriteString(h, g_account_period_uid + "\r\n");
   FileWriteString(h, (string)((long)g_account_start_time) + "\r\n");
   FileWriteString(h, NumStr(g_account_start_balance, 2) + "\r\n");
   FileClose(h);
}

// Po restarcie EA: odtwórz agregaty z istniejącego wiersza CSV (ten sam period_uid), żeby Upsert nie wyzerował liczników
bool HydrateAccountAgeFromCsv(const string uid, const ulong login)
{
   string filename = "AccountAgeReport.csv";
   if(!FileExistsCommon(filename))
      return false;
   int h = FileOpen(filename, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   string content = "";
   while(!FileIsEnding(h))
      content += FileReadString(h) + "\n";
   FileClose(h);
   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");
   string lines[];
   int nlines = StringSplit(content, (ushort)'\n', lines);
   string key_uid = uid;
   NormalizeAccountAgeUidField(key_uid);
   for(int i = 0; i < nlines; i++)
   {
      if(StringLen(lines[i]) == 0)
         continue;
      if(i < 2)
         continue;
      string parts[];
      int pcnt = StringSplit(lines[i], (ushort)';', parts);
      if(pcnt < 24)
         continue;
      string file_uid = parts[0];
      if(!NormalizeAccountAgeUidField(file_uid))
         continue;
      if(file_uid != key_uid)
         continue;
      string row_konto = parts[1];
      StringTrimLeft(row_konto);
      StringTrimRight(row_konto);
      if(row_konto != (string)login)
         continue;

      double row_start_bal = ParseFlexibleDouble(parts[5]);
      if(row_start_bal > 0.0)
         g_account_start_balance = row_start_bal;

      g_account_max_equity       = ParseFlexibleDouble(parts[7]);
      g_session_max_dd           = ParseFlexibleDouble(parts[8]);
      g_session_max_total_lot    = ParseFlexibleDouble(parts[9]);
      g_active_trading_days      = (int)StringToInteger(parts[11]);
      double pf                  = ParseFlexibleDouble(parts[14]);
      g_total_trades             = (int)StringToInteger(parts[15]);
      double wr                  = ParseFlexibleDouble(parts[16]);
      g_win_trades               = 0;
      if(g_total_trades > 0 && wr >= 0.0)
         g_win_trades = (int)MathFloor(wr * (double)g_total_trades / 100.0 + 0.5);
      if(g_win_trades > g_total_trades)
         g_win_trades = g_total_trades;
      g_max_consecutive_wins     = (int)StringToInteger(parts[18]);
      g_max_consecutive_losses   = (int)StringToInteger(parts[19]);
      double avg_min             = ParseFlexibleDouble(parts[20]);
      if(g_total_trades > 0)
         g_total_trade_duration_sec = avg_min * 60.0 * (double)g_total_trades;
      else
         g_total_trade_duration_sec = 0.0;
      g_total_sessions           = (int)StringToInteger(parts[23]);

      if(pf >= 999.0)
      {
         g_sum_profit = 1.0;
         g_sum_loss   = 0.0;
      }
      else if(pf > 0.001)
      {
         g_sum_profit = pf;
         g_sum_loss   = 1.0;
      }
      else
      {
         g_sum_profit = 0.0;
         g_sum_loss   = 0.0;
      }

      Print("HydrateAccountAgeFromCsv: OK uid=", uid,
            " trades=", g_total_trades, " sessions=", g_total_sessions);
      return true;
   }
   Print("HydrateAccountAgeFromCsv: brak wiersza dla uid=", uid, " login=", (string)login);
   return false;
}

// ---------------------------------------------------------
// Account Age Report – upsert wiersza: tworzy nowy przy resecie, aktualizuje po każdej sesji
// Klucz: period_uid (twardy ID okresu życia). Zamrożone wiersze (g_account_age_reported) nie są dotykane.
// Nie zmienia logiki ani plików pozostałych 4 raportów.
// ---------------------------------------------------------
void UpsertAccountAgeRow()
{
   // Nie aktualizujemy zamrożonego wiersza (koniec życia konta)
   if(g_account_age_reported)
      return;

   // Upewnij się, że mamy UID okresu (start EA lub RESET). UID = login + "_" + start_time(server_seconds)
   if(g_account_period_uid == "" && g_account_start_time > 0)
      g_account_period_uid = (string)g_login + "_" + (string)((long)g_account_start_time);

   // Diagnostyka: wejście do upsertu – to ma się pojawiać po resecie i po każdej zakończonej sesji
   Print("UpsertAccountAgeRow: ENTER konto=", (string)g_login,
         " uid=", g_account_period_uid,
         " start_time_server=", TimeToString(g_account_start_time, TIME_DATE|TIME_MINUTES),
         " session_id=", (string)g_session_id,
         " session_end_time=", TimeToString(g_session_end_time, TIME_DATE|TIME_MINUTES));

   string new_line   = BuildAccountAgeLine();
   string key_uid    = g_account_period_uid;
   string key_konto  = (string)g_login;
   string key_start  = TimeToString(ToLocal(g_account_start_time), TIME_DATE | TIME_MINUTES);

   EnsureHeaderAccountAge();

   string filename = "AccountAgeReport.csv";
   // Używamy FILE_ANSI + czytanie linia-po-linii, żeby zawsze dostać poprawne nlines
   int h = FileOpen(filename, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      // Plik nie istnieje – awaryjnie utwórz z nagłówkiem i pierwszym wierszem
      int hw = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(hw == INVALID_HANDLE) { Print("UpsertAccountAgeRow: create failed err=", GetLastError()); return; }
      FileWriteString(hw, "sep=;\r\n");
      FileWriteString(hw,
         "period_uid;konto;account_start_date;account_end_date;session_id;"
         "account_start_balance;account_end_balance;max_equity_history;"
         "max_drawdown_pln;total_lot_current_max;account_age_days;"
         "active_trading_days;total_net_profit;max_drawdown_percent;"
         "profit_factor;total_trades;win_rate_percent;avg_trade_profit;"
         "max_consecutive_wins;max_consecutive_losses;avg_trade_duration_min;"
         "most_traded_symbol;market_session_failure;total_sessions\r\n");
      FileWriteString(hw, new_line + "\r\n");
      FileClose(hw);
      Print("UpsertAccountAgeRow: created file and header (fallback), first line for konto=", key_konto,
            " uid=", key_uid, " start_date=", key_start);
      SaveAccountAgeSidecar();
      return;
   }

   long sz = FileSize(h);
   if(sz <= 0)
   {
      FileClose(h);
      int hw = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(hw == INVALID_HANDLE) return;
      FileWriteString(hw, "sep=;\r\n");
      FileWriteString(hw,
         "period_uid;konto;account_start_date;account_end_date;session_id;"
         "account_start_balance;account_end_balance;max_equity_history;"
         "max_drawdown_pln;total_lot_current_max;account_age_days;"
         "active_trading_days;total_net_profit;max_drawdown_percent;"
         "profit_factor;total_trades;win_rate_percent;avg_trade_profit;"
         "max_consecutive_wins;max_consecutive_losses;avg_trade_duration_min;"
         "most_traded_symbol;market_session_failure;total_sessions\r\n");
      FileWriteString(hw, new_line + "\r\n");
      FileClose(hw);
      Print("UpsertAccountAgeRow: repaired empty file with header, first line for konto=", key_konto,
            " uid=", key_uid, " start_date=", key_start);
      SaveAccountAgeSidecar();
      return;
   }

   // Czytaj linia-po-linii (FILE_TXT), żeby uniknąć problemów z UTF-16 i FileSize()
   string content = "";
   while(!FileIsEnding(h))
   {
      string ln = FileReadString(h);
      // Zapisz linię z jednolitym '\n' jako separator w pamięci
      content += ln + "\n";
   }
   FileClose(h);

   // Normalizacja zakończeń linii (definicja: NIGDY nie nadpisujemy wierszy innych kont)
   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");

   string lines[];
   int nlines = StringSplit(content, (ushort)'\n', lines);
   if(nlines <= 0) return;

   // Usuń znak '\r' z końca każdej linii (na wszelki wypadek)
   for(int i = 0; i < nlines; i++)
   {
      string s = lines[i];
      int    l = StringLen(s);
      if(l > 0 && StringGetCharacter(s, l - 1) == '\r')
         s = StringSubstr(s, 0, l - 1);
      lines[i] = s;
   }

   // Log: liczba linii i rozmiar – do diagnozy nadpisywania wierszy innych kont
   Print("UpsertAccountAgeRow: read file nlines=", nlines, " sz=", (long)sz, " konto=", key_konto, " uid=", key_uid, " key_start=", key_start);

   // Twarda kontrola nagłówka – napraw, jeśli brak lub uszkodzony
   string expected_header =
      "period_uid;konto;account_start_date;account_end_date;session_id;"
      "account_start_balance;account_end_balance;max_equity_history;"
      "max_drawdown_pln;total_lot_current_max;account_age_days;"
      "active_trading_days;total_net_profit;max_drawdown_percent;"
      "profit_factor;total_trades;win_rate_percent;avg_trade_profit;"
      "max_consecutive_wins;max_consecutive_losses;avg_trade_duration_min;"
      "most_traded_symbol;market_session_failure;total_sessions";

   // Stary nagłówek (bez period_uid) – używany do automatycznego upgrade danych w pamięci
   string old_header =
      "konto;account_start_date;account_end_date;session_id;"
      "account_start_balance;account_end_balance;max_equity_history;"
      "max_drawdown_pln;total_lot_current_max;account_age_days;"
      "active_trading_days;total_net_profit;max_drawdown_percent;"
      "profit_factor;total_trades;win_rate_percent;avg_trade_profit;"
      "max_consecutive_wins;max_consecutive_losses;avg_trade_duration_min;"
      "most_traded_symbol;market_session_failure;total_sessions";

   bool header_fixed = false;

   if(nlines < 2)
   {
      // Definicja CORE: NIGDY nie nadpisujemy wierszy innych kont. Gdy plik jest duży, ale nlines<2 (błąd parsowania), nie zastępuj całości – dopisz na końcu.
      if(sz > 250)
      {
         Print("UpsertAccountAgeRow: WARNING nlines=", nlines, " but sz=", (long)sz, " – possible other accounts data, APPEND only for konto=", key_konto);
         int hAppend = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
         if(hAppend != INVALID_HANDLE)
         {
            FileSeek(hAppend, 0, SEEK_END);
            FileWriteString(hAppend, new_line + "\r\n");
            FileClose(hAppend);
         }
         Print("UpsertAccountAgeRow: appended row (no overwrite) for konto=", key_konto, " start_date=", key_start);
         SaveAccountAgeSidecar();
         return;
      }
      // Plik naprawdę minimalny (sep lub sep+header) – odbuduj w miejscu
      ArrayResize(lines, 3);
      lines[0] = "sep=;";
      lines[1] = expected_header;
      lines[2] = new_line;
      nlines   = 3;
      header_fixed = true;
      Print("UpsertAccountAgeRow: replaced minimal file (nlines<2, sz<=250) for konto=", key_konto);
   }
   else
   {
      // Jeśli plik ma stary nagłówek (bez period_uid), wykonaj upgrade w pamięci bez gubienia wierszy
      if(lines[1] == old_header)
      {
         Print("UpsertAccountAgeRow: detected OLD header (no period_uid). Upgrading existing rows in memory for ", filename);
         lines[0] = "sep=;";
         lines[1] = expected_header;
         header_fixed = true;

         // Konwersja: dodaj period_uid jako pierwszą kolumnę w każdej linii danych
         for(int i = 2; i < nlines; i++)
         {
            if(StringLen(lines[i]) == 0) continue;
            string op[];
            if(StringSplit(lines[i], (ushort)';', op) < 2) continue; // potrzebujemy konto + account_start_date

            string konto_old = op[0];
            StringTrimLeft(konto_old);
            StringTrimRight(konto_old);

            string start_old = op[1];
            StringTrimLeft(start_old);
            StringTrimRight(start_old);
            datetime start_dt = StringToTime(start_old);
            string uid_old = (start_dt > 0) ? (konto_old + "_" + (string)start_dt) : (konto_old + "_UNKNOWN");

            lines[i] = uid_old + ";" + lines[i];
         }
      }
      else if(lines[0] != "sep=;" || lines[1] != expected_header)
      {
         Print("UpsertAccountAgeRow: header mismatch or missing, repairing header in ", filename);
         lines[0] = "sep=;";
         lines[1] = expected_header;
         header_fixed = true;
      }
   }

   bool found = false;
   int  first_match_line = -1;
   int  dup_removed = 0;
   string first_mismatch_uid = "";
   for(int i = 2; i < nlines; i++)
   {
      if(StringLen(lines[i]) == 0) continue;
      string parts[];
      int pcnt = StringSplit(lines[i], (ushort)';', parts);
      if(pcnt < 1) continue;

      // Jeśli nagłówek jest już w nowym schemacie, ale wiersz danych nadal ma stary format (bez UID),
      // to napraw ten wiersz w miejscu (żeby kolejne upserty nie robiły APPEND).
      // Stary format = 23 kolumn, gdzie parts[0]=konto, parts[1]=account_start_date.
      if(lines[1] == expected_header && pcnt == 23)
      {
         string konto_old = parts[0];
         StringTrimLeft(konto_old);
         StringTrimRight(konto_old);

         string start_old = parts[1];
         StringTrimLeft(start_old);
         StringTrimRight(start_old);

         datetime start_dt = StringToTime(start_old);
         string uid_old = (start_dt > 0) ? (konto_old + "_" + (string)start_dt) : (konto_old + "_UNKNOWN");

         // Jeśli to dokładnie nasz okres życia – wykonaj UPDATE zamiast APPEND
         if(uid_old == key_uid)
         {
            if(first_match_line < 0)
               first_match_line = i;
            else
            {
               lines[i] = ""; // duplikat tego samego UID – usuniemy przy kompakcji
               dup_removed++;
            }
            // nie break – chcemy wyczyścić wszystkie duplikaty tego samego UID
            continue;
         }

         // W przeciwnym razie tylko dołącz UID, żeby plik był spójny (bez gubienia wierszy)
         lines[i] = uid_old + ";" + lines[i];
         header_fixed = true;
         continue;
      }

      // Normalizacja klucza period_uid (twardy klucz rekordu)
      string file_uid = parts[0];
      StringTrimLeft(file_uid);
      StringTrimRight(file_uid);
      // Usuń ewentualny BOM na początku pola (rzadkie, ale psuje porównania stringów)
      if(StringLen(file_uid) > 0 && StringGetCharacter(file_uid, 0) == 0xFEFF)
         file_uid = StringSubstr(file_uid, 1);
      // Excel/csv czasem dodaje apostrof/cudzysłów – usuń na brzegach
      if(StringLen(file_uid) > 0 && (StringGetCharacter(file_uid, 0) == '\'' || StringGetCharacter(file_uid, 0) == '\"'))
         file_uid = StringSubstr(file_uid, 1);
      int lu = StringLen(file_uid);
      if(lu > 0 && (StringGetCharacter(file_uid, lu - 1) == '\'' || StringGetCharacter(file_uid, lu - 1) == '\"'))
         file_uid = StringSubstr(file_uid, 0, lu - 1);

      if(file_uid == key_uid)
      {
         if(first_match_line < 0)
            first_match_line = i;
         else
         {
            lines[i] = ""; // duplikat tego samego UID – usuniemy przy kompakcji
            dup_removed++;
         }
         // nie break – chcemy wyczyścić wszystkie duplikaty tego samego UID
         continue;
      }

      // Migracja: stare UID mogło być zapisane jako login_YYYY.MM.DD HH:MI:SS (tekst).
      // Jeśli pasuje prefix login_, spróbuj przeliczyć suffix na server_seconds i porównać z key_uid.
      string prefix = key_konto + "_";
      if(StringLen(file_uid) > StringLen(prefix) && StringSubstr(file_uid, 0, StringLen(prefix)) == prefix)
      {
         string suffix = StringSubstr(file_uid, StringLen(prefix));
         StringTrimLeft(suffix);
         StringTrimRight(suffix);

         datetime dt = StringToTime(suffix);
         if(dt > 0)
         {
            string numeric_uid = key_konto + "_" + (string)((long)dt);
            if(numeric_uid == key_uid)
            {
               if(first_match_line < 0)
                  first_match_line = i;
               else
               {
                  lines[i] = ""; // duplikat tego samego UID – usuniemy przy kompakcji
                  dup_removed++;
               }
               // nie break – chcemy wyczyścić wszystkie duplikaty tego samego UID
               header_fixed = true;
               continue;
            }
         }
      }

      // Diagnostyka: zapamiętaj pierwszy UID w pliku (jeśli update nie trafi)
      if(first_mismatch_uid == "")
         first_mismatch_uid = file_uid;
   }

   // Jeśli znaleźliśmy choć jedną linię z tym UID: zaktualizuj pierwszą i usuń duplikaty
   if(first_match_line >= 0)
   {
      lines[first_match_line] = new_line;
      found = true;
      Print("UpsertAccountAgeRow: UPDATING UID row at line ", first_match_line, " for konto=", key_konto, " uid=", key_uid,
            " dup_removed=", dup_removed);

      // Kompakcja tablicy: usuń puste linie po deduplikacji
      int w = 0;
      for(int r = 0; r < nlines; r++)
      {
         if(r < 2)
         {
            lines[w++] = lines[r];
            continue;
         }
         if(StringLen(lines[r]) == 0)
            continue;
         lines[w++] = lines[r];
      }
      if(w != nlines)
      {
         ArrayResize(lines, w);
         nlines = w;
         header_fixed = true; // zapisujemy plik w poprawionej postaci (bez duplikatów)
      }
   }

   // Jeśli nie znaleźliśmy wiersza do update, pokaż diagnostykę po UID (najważniejsze dla tego schematu)
   if(!found)
   {
      Print("UpsertAccountAgeRow: WARNING uid not found for konto=", key_konto,
            " expected_uid=", key_uid,
            " first_seen_uid=", first_mismatch_uid);
   }

   if(!found)
   {
      ArrayResize(lines, nlines + 1);
      lines[nlines] = new_line;
      nlines++;
      Print("UpsertAccountAgeRow: APPENDING new row (total data rows now ", nlines - 2, ") for konto=", key_konto);
   }

   // Zapis całego pliku z powrotem (zachowujemy WSZYSTKIE linie – wiersze innych kont NIGDY nie są usuwane)
   int hw = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(hw == INVALID_HANDLE)
   {
      Print("UpsertAccountAgeRow: write failed err=", GetLastError());
      return;
   }
   for(int i = 0; i < nlines; i++)
      FileWriteString(hw, lines[i] + "\r\n");
   FileClose(hw);

   SaveAccountAgeSidecar();

   Print("UpsertAccountAgeRow: upsert OK for konto=", key_konto,
         " start_date=", key_start,
         " found_existing=", (found ? "true" : "false"),
         " header_fixed=", (header_fixed ? "true" : "false"));
}

// ---------------------------------------------------------
// Account Age Report – zapis końcowego wiersza okresu życia konta (legacy: używaj UpsertAccountAgeRow)
// ---------------------------------------------------------
void AppendAccountAgeRowFinal()
{
   // Zabezpieczenie przed podwójnym zapisem tego samego okresu
   if(g_account_age_reported)
      return;

   // Ustal daty w czasie lokalnym
   datetime start_local = ToLocal(g_account_start_time);
   datetime end_local   = ToLocal(g_session_end_time > 0 ? g_session_end_time : TimeCurrent());

   // Oblicz wiek konta w dniach (pełne dni między startem a końcem)
   int age_days = 0;
   if(g_account_start_time > 0 && g_session_end_time > 0)
      age_days = (int)((g_session_end_time - g_account_start_time) / (60 * 60 * 24));

   // Wylicz wynik netto okresu życia konta
   double account_end_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double total_net_profit    = account_end_balance - g_account_start_balance;

   // Maksymalny drawdown w PLN – na bazie sesyjnego DD z ostatniej sesji
   double max_dd_pln = g_session_max_dd; // wartość ujemna; możesz zmienić na MathAbs, jeśli wolisz dodatnią

   // Maksymalny drawdown w %
   double max_dd_percent = 0.0;
   if(g_account_start_balance > 0.0)
      max_dd_percent = (MathAbs(g_session_max_dd) / g_account_start_balance) * 100.0;

   // Profit factor w okresie życia konta
   double profit_factor = 0.0;
   if(g_sum_loss > 0.0)
      profit_factor = g_sum_profit / g_sum_loss;
   else if(g_sum_profit > 0.0)
      profit_factor = 999.99;
   else
      profit_factor = 0.0;

   // Win rate w %
   double win_rate = 0.0;
   if(g_total_trades > 0)
      win_rate = (double)g_win_trades * 100.0 / (double)g_total_trades;

   // Średni zysk na transakcję
   double avg_trade_profit = 0.0;
   if(g_total_trades > 0)
      avg_trade_profit = (g_total_trades != 0 ? total_net_profit / (double)g_total_trades : 0.0);

   // Średni czas trwania transakcji (minuty)
   double avg_trade_duration_min = 0.0;
   if(g_total_trades > 0)
      avg_trade_duration_min = g_total_trade_duration_sec / 60.0 / (double)g_total_trades;

   // Most traded symbol – na razie puste, można rozszerzyć o liczniki symboli
   string most_traded_symbol = "";

   // Sesja rynku, w której nastąpił koniec życia konta
   string market_session_failure = GetMarketSessionFailure(end_local);

   // Upewnij się, że nagłówek pliku istnieje
   EnsureHeaderAccountAge();

   // Otwórz plik w trybie dopisywania na końcu
   int h = FileOpen("AccountAgeReport.csv", FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("AppendAccountAgeRowFinal: FileOpen failed, err=", GetLastError());
      return;
   }

   // Przesuń wskaźnik zapisu na koniec pliku
   FileSeek(h, 0, SEEK_END);

   // Zbuduj linię CSV zgodnie ze schematem (23 kolumny, separator ;)
   string line = "";

   // konto
   line += (string)g_login + ";";

   // account_start_date / account_end_date (czas lokalny, do minut)
   line += TimeToString(start_local, TIME_DATE | TIME_MINUTES) + ";";
   line += TimeToString(end_local,   TIME_DATE | TIME_MINUTES) + ";";

   // session_id końcowej sesji
   line += (string)g_session_id + ";";

   // salda start/end
   line += NumStr(g_account_start_balance, 2) + ";";
   line += NumStr(account_end_balance,      2) + ";";

   // max_equity_history
   line += NumStr(g_account_max_equity, 2) + ";";

   // max_drawdown_pln
   line += NumStr(max_dd_pln, 2) + ";";

   // total_lot_current_max – użyj maksymalnego total lot z ostatniej sesji
   line += LotStr(g_session_max_total_lot) + ";";

   // account_age_days
   line += (string)age_days + ";";

   // active_trading_days
   line += (string)g_active_trading_days + ";";

   // total_net_profit
   line += NumStr(total_net_profit, 2) + ";";

   // max_drawdown_percent
   line += NumStr(max_dd_percent, 2) + ";";

   // profit_factor
   line += NumStr(profit_factor, 2) + ";";

   // total_trades
   line += (string)g_total_trades + ";";

   // win_rate_percent
   line += NumStr(win_rate, 2) + ";";

   // avg_trade_profit
   line += NumStr(avg_trade_profit, 2) + ";";

   // max_consecutive_wins / losses
   line += (string)g_max_consecutive_wins   + ";";
   line += (string)g_max_consecutive_losses + ";";

   // avg_trade_duration_min
   line += NumStr(avg_trade_duration_min, 2) + ";";

   // most_traded_symbol
   line += most_traded_symbol + ";";

   // market_session_failure
   line += market_session_failure + ";";

   // total_sessions
   line += (string)g_total_sessions;

   // Zapisz linię z klasycznym CRLF
   FileWriteString(h, line + "\r\n");

   FileClose(h);

   // Diagnostyka zapisu końcowego wiersza okresu życia konta
   Print("AccountAgeReport: appended row for login=",
         (string)g_login,
         " start_balance=", g_account_start_balance,
         " end_balance=", account_end_balance,
         " total_sessions=", g_total_sessions);

   // Zaznacz okres jako już zraportowany
   g_account_age_reported = true;
}

// -------------------- runtime updates --------------------
void UpdateSessionMetrics()
{
   double total_vol = 0.0, max_single = 0.0;
   int open_cnt = CountFilteredPositions(total_vol, max_single);

   // session start / end detection
   if(!g_session_active && open_cnt > 0)
   {
      StartSession();
   }
   else if(g_session_active && open_cnt == 0)
   {
      // Ustaw koniec sesji (server time) PRZED przetwarzaniem deali,
      // aby w LogDealPerAccount() był dostępny poprawny czas zakończenia
      g_session_end_time = TimeCurrent();

      // dociągnij closing deals
      ProcessCloseDeals();

      // złap finalny DD i dograj brakujące progi
      double eq_final = AccountInfoDouble(ACCOUNT_EQUITY);
      double dd_final = eq_final - g_session_start_equity;
      if(dd_final < g_session_max_dd)
         g_session_max_dd = dd_final;

      datetime now_min = FloorToMinute(TimeCurrent());
      while(g_session_max_dd <= g_next_dd_threshold)
      {
         LogThreshold(now_min, g_next_dd_threshold, eq_final);
         g_next_dd_threshold -= MathAbs(InpDDStep);
      }

      // DEBUG: właśnie uznaliśmy, że sesja się kończy
      Print("DEBUG EndSession condition: open_cnt=0, calling EndSessionFinalize, session_id=", g_session_id);

      // Account Age Report – zwiększ licznik sesji w bieżącym okresie życia konta
      g_total_sessions++;

      EndSessionFinalize();

      g_bucket_minute    = 0;
      g_bucket_profit    = 0.0;
      g_bucket_has_close = false;
      return;
   }

   if(!g_session_active)
      return;

   // --- margin metrics snapshot ---
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);

   if(margin > 0.0 && equity > 0.0)
   {
      double margin_level = (equity / margin) * 100.0; // Margin Level %
      double margin_used  = (margin / equity) * 100.0; // zajęcie marginu w %

      if(margin_level < g_min_margin_level) g_min_margin_level = margin_level;
      if(margin_used  > g_max_margin_used)  g_max_margin_used  = margin_used;

      // Vantage: margin call ~50%, stop out ~20% (Margin Level)
      if(!g_seen_margin_call && margin_level <= 50.0)
      {
         g_seen_margin_call = true;
         g_margin_comment   = "MARGIN_CALL";
      }

      // ============================================================
      // NOWE ALERTY – DRAWDOWN % (strata kapitału)
      // ============================================================
      double dd_percent = 0;
      if(g_session_start_equity > 0)
         dd_percent = (g_session_start_equity - equity) / g_session_start_equity * 100.0;
      if(dd_percent < 0) dd_percent = 0;

      if(dd_percent >= 60.0 && g_dd_alert_sent < 60.0)
      {
         g_dd_alert_sent = 60.0;
         string msg = StringFormat("DRAWDOWN ALERT 60% | konto=%s equity=%.2f start=%.2f dd%%=%.2f",
                     (string)g_login, equity, g_session_start_equity, dd_percent);
         Alert(msg); Print(msg); SendNotification(msg);
      }
      else if(dd_percent >= 40.0 && g_dd_alert_sent < 40.0)
      {
         g_dd_alert_sent = 40.0;
         string msg = StringFormat("DRAWDOWN ALERT 40% | konto=%s equity=%.2f start=%.2f dd%%=%.2f",
                     (string)g_login, equity, g_session_start_equity, dd_percent);
         Alert(msg); Print(msg); SendNotification(msg);
      }
      else if(dd_percent >= 20.0 && g_dd_alert_sent < 20.0)
      {
         g_dd_alert_sent = 20.0;
         string msg = StringFormat("DRAWDOWN ALERT 20% | konto=%s equity=%.2f start=%.2f dd%%=%.2f",
                     (string)g_login, equity, g_session_start_equity, dd_percent);
         Alert(msg); Print(msg); SendNotification(msg);
      }

      // ============================================================
      // NOWE ALERTY – MARGIN LEVEL (wg Vantage)
      // ============================================================
      if(margin_level <= 20.0 && g_margin_level_alert_sent < 20.0)
      {
         g_margin_level_alert_sent = 20.0;
         string msg = StringFormat("MARGIN LEVEL ALERT 20% (STOP OUT) | konto=%s level=%.2f%%",
                     (string)g_login, margin_level);
         Alert(msg); Print(msg); SendNotification(msg);
      }
      else if(margin_level <= 50.0 && g_margin_level_alert_sent < 50.0)
      {
         g_margin_level_alert_sent = 50.0;
         string msg = StringFormat("MARGIN LEVEL ALERT 50% (MARGIN CALL) | konto=%s level=%.2f%%",
                     (string)g_login, margin_level);
         Alert(msg); Print(msg); SendNotification(msg);
      }
      else if(margin_level <= 80.0 && g_margin_level_alert_sent < 80.0)
      {
         g_margin_level_alert_sent = 80.0;
         string msg = StringFormat("MARGIN LEVEL ALERT 80% (OSTRZEŻENIE) | konto=%s level=%.2f%%",
                     (string)g_login, margin_level);
         Alert(msg); Print(msg); SendNotification(msg);
      }

      // ============================================================
      // STARE ALERTY (możesz je usunąć, jeśli nie są już potrzebne)
      // ============================================================
      /*
      double next_level = 0.0;
      if(margin_used >= 80.0)      next_level = 80.0;
      else if(margin_used >= 60.0) next_level = 60.0;
      else if(margin_used >= 40.0) next_level = 40.0;
      else if(margin_used >= 20.0) next_level = 20.0;

      if(next_level > 0.0 && next_level > g_margin_alert_level)
      {
         g_margin_alert_level = next_level;
         string msg = StringFormat(
            "MARGIN USED ALERT %.0f%% | konto=%s equity=%.2f margin=%.2f used=%.2f%% level=%.2f%%",
            next_level,
            (string)g_login,
            equity,
            margin,
            margin_used,
            margin_level
         );
         Alert(msg);
         Print(msg);
         SendNotification(msg);
      
         int err = GetLastError();
         Print("NotifySessionEnd: SendNotification err=", err);
         ResetLastError();
      }
      */
   }

   // --- worst floating P/L among OPEN positions in session ---
   double worst = 0.0;
   bool has = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(!PassPositionFiltersByIndex(i)) continue;
      double pl = PositionGetDouble(POSITION_PROFIT);
      if(!has || pl < worst) { worst = pl; has = true; }
   }
   if(has && !g_seen_stop_out)
   {
      if(!g_worst_floating_pl || worst < g_worst_floating_pl)
         g_worst_floating_pl = worst;
   }

   // update lot maxima within session
   if(max_single > g_session_max_single_lot) g_session_max_single_lot = max_single;
   if(total_vol  > g_session_max_total_lot)  g_session_max_total_lot  = total_vol;

   // ============================================================
   // TOTAL_LOT_ALERT — progi sumy lotów (otwarte pozycje w sesji, ten sam filtr co sesja)
   // LIVE (produkcja): co 10 lot -> "10Lots Opened!", "20Lots Opened!", ...
   // Pozostałe konta: progi 50 / 100 / 150 / 200
   // ============================================================
   {
      double tl = g_session_max_total_lot;
      if(g_is_live_account)
      {
         double next_live_threshold = g_total_lot_alert_sent + 10.0;
         while(tl >= next_live_threshold)
         {
            g_total_lot_alert_sent = next_live_threshold;
            string msg = StringFormat("%.0fLots Opened!", next_live_threshold);
            Alert(msg); Print(msg); SendNotification(msg);
            next_live_threshold += 10.0;
         }
      }
      else
      {
         if(tl >= 50.0 && g_total_lot_alert_sent < 50.0)
         {
            g_total_lot_alert_sent = 50.0;
            string msg = StringFormat("TOTAL_LOT_ALERT 50 | konto=%s total_lot=%.2f (max w sesji)",
                       (string)g_login, tl);
            Alert(msg); Print(msg); SendNotification(msg);
         }
         if(tl >= 100.0 && g_total_lot_alert_sent < 100.0)
         {
            g_total_lot_alert_sent = 100.0;
            string msg = StringFormat("TOTAL_LOT_ALERT 100 | konto=%s total_lot=%.2f (max w sesji)",
                       (string)g_login, tl);
            Alert(msg); Print(msg); SendNotification(msg);
         }
         if(tl >= 150.0 && g_total_lot_alert_sent < 150.0)
         {
            g_total_lot_alert_sent = 150.0;
            string msg = StringFormat("TOTAL_LOT_ALERT 150 | konto=%s total_lot=%.2f (max w sesji)",
                       (string)g_login, tl);
            Alert(msg); Print(msg); SendNotification(msg);
         }
         if(tl >= 200.0 && g_total_lot_alert_sent < 200.0)
         {
            g_total_lot_alert_sent = 200.0;
            string msg = StringFormat("TOTAL_LOT_ALERT 200 | konto=%s total_lot=%.2f (max w sesji)",
                       (string)g_login, tl);
            Alert(msg); Print(msg); SendNotification(msg);
         }
      }
   }

   // update drawdown within session
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = eq - g_session_start_equity;
   if(dd < g_session_max_dd)
      g_session_max_dd = dd;

   // przenieś "so far" z sesji do dnia (po aktualizacji sesji!)
   if(g_session_max_dd         < g_day_max_dd)         g_day_max_dd         = g_session_max_dd;
   if(g_session_max_single_lot > g_day_max_single_lot) g_day_max_single_lot = g_session_max_single_lot;
   if(g_session_max_total_lot  > g_day_max_total_lot)  g_day_max_total_lot  = g_session_max_total_lot;

   // Account Age Report – aktualizacja maksymalnego equity w okresie życia konta
   if(eq > g_account_max_equity)
      g_account_max_equity = eq;

   // log thresholds: every time we go below -1000, -2000, ...
   datetime now_min2 = FloorToMinute(TimeCurrent());
   while(g_session_max_dd <= g_next_dd_threshold)
   {
      LogThreshold(now_min2, g_next_dd_threshold, eq);
      g_next_dd_threshold -= MathAbs(InpDDStep);
   }

   // trigger FAILED jeżeli equity/balance < 1000
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(eq < 1000.0 || bal < 1000.0)
      g_day_failed = true;
}
// ---------------------------------------------------------
// Przetwarza zamknięte deale w bieżącej sesji
// ---------------------------------------------------------
void ProcessCloseDeals()
{

Print("ProcessCloseDeals: wywołane z g_session_active=", g_session_active,
      " g_session_id=", g_session_id,
      " g_last_deal_ticket_logged=", g_last_deal_ticket_logged);
      
   datetime now_server = TimeCurrent();

   // zakres historii: od początku SESJI (jeśli znany) albo od początku dnia do TERAZ
   datetime from_server;
   if(g_session_start_time > 0)
      from_server = g_session_start_time;
   else
      from_server = DayStart(now_server);   // fallback gdyby coś poszło nie tak

   datetime to_server = now_server;

   if(!HistorySelect(from_server, to_server))
   {
      PrintFormat("ProcessCloseDeals: HistorySelect failed from=%s to=%s err=%d",
                  TimeToString(from_server, TIME_DATE|TIME_MINUTES),
                  TimeToString(to_server,   TIME_DATE|TIME_MINUTES),
                  GetLastError());
      return;
   }

   int total = HistoryDealsTotal();

   // ---------------------------------------------------------
   // 1) PIERWSZE PRZEJŚCIE: policz total PROFIT ONLY dla bieżącej sesji
   // ---------------------------------------------------------
   double session_total_profit = 0.0;

   // Diagnostyka "rozjazdu": sesja jest domykana, ale total_profit_only wychodzi 0.0,
   // a deale OUT/INOUT z DEAL_PROFIT==0.0 moga miec niezerowe (DEAL_COMMISSION/DEAL_SWAP)
   // i dopiero po chwili uaktualniac sie w historii.
   int    diag_out_inout_deals          = 0;
   int    diag_out_inout_profit_nonzero = 0;
   int    diag_out_inout_profit_zero    = 0;

   for(int i = 0; i < total; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

      // tylko rzeczywiste wyjścia z pozycji
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;

      // filtr symbolu
      string sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
      if(InpSymbolFilter != "" && sym != InpSymbolFilter)
         continue;

      // filtr magic'a
      long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(InpMagicFilter != -1 && magic != InpMagicFilter)
         continue;

      // profit bez swap/commission (to jest nasza profit-only metryka)
      double p = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      // Liczymy statystyki diagnostyczne jeszcze przed anti-duplicate,
      // bo w retry chcemy sprawdzic czy "brak profitów" wynika z p==0 na skanie.
      diag_out_inout_deals++;
      if(p == 0.0)
      {
         diag_out_inout_profit_zero++;
         continue;
      }
      else
      {
         diag_out_inout_profit_nonzero++;
      }

      long deal_time_msc = (long)HistoryDealGetInteger(deal_ticket, DEAL_TIME_MSC);

      // ANTI‑DUPLICATE: pomijamy wszystko co już zalogowane
      if(deal_ticket <= g_last_deal_ticket_logged &&
         deal_time_msc <= g_last_deal_time_msc_logged)
         continue;

      if(deal_ticket <= g_last_deal_ticket_logged)
         continue;

      // tutaj jesteśmy już w oknie SESJI (bo HistorySelect jest od g_session_start_time)
      session_total_profit += p;
   }

   // Retry jeżeli w pierwszym skanie profit-only wyszedl 0, a history contains OUT/INOUT deale (z p==0),
   // co może oznaczac opóznione uaktualnienie DEAL_PROFIT w MT5.
   bool do_retry_late_profit = false;
   if(session_total_profit == 0.0 &&
      diag_out_inout_deals > 0 &&
      diag_out_inout_profit_nonzero == 0 &&
      InpLateProfitRetrySeconds > 0)
   {
      do_retry_late_profit = true;
   }

   PrintFormat("ProcessCloseDeals: session_id=%d total_profit_only=%.2f (konto=%I64u) from=%s to=%s",
               g_session_id, session_total_profit, g_login,
               TimeToString(from_server, TIME_DATE|TIME_MINUTES),
               TimeToString(to_server,   TIME_DATE|TIME_MINUTES));

   if(do_retry_late_profit)
   {
      PrintFormat("ProcessCloseDeals: LATE PROFIT suspected. session_id=%d sleeping=%d sec; out_inout_deals=%d p!=0=%d p==0=%d",
                  g_session_id, InpLateProfitRetrySeconds, diag_out_inout_deals,
                  diag_out_inout_profit_nonzero, diag_out_inout_profit_zero);

      // Diagnostyka: wypisz pierwsze deale OUT/INOUT z DEAL_PROFIT==0, ktore wchodza do tego samego HistorySelect.
      // To ma byc twardy dowod: czy te ticket'y z raportu w ogole pojawily sie w historii dla sesji.
      if(InpLateProfitRetrySampleLimit > 0)
      {
         int printed = 0;
         for(int i = 0; i < total && printed < InpLateProfitRetrySampleLimit; i++)
         {
            ulong deal_ticket = HistoryDealGetTicket(i);
            if(deal_ticket == 0)
               continue;

            long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
               continue;

            string sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            if(InpSymbolFilter != "" && sym != InpSymbolFilter)
               continue;

            long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
            if(InpMagicFilter != -1 && magic != InpMagicFilter)
               continue;

            double p = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            if(p != 0.0)
               continue;

            double comm = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
            double net  = p + comm + swap;

            long deal_time_msc = (long)HistoryDealGetInteger(deal_ticket, DEAL_TIME_MSC);
            datetime deal_time = (datetime)(deal_time_msc / 1000);

            printed++;
            PrintFormat("DEBUG ProcessCloseDeals pre-retry p==0: session_id=%d ticket=%I64u time=%s p=%.2f comm=%.2f swap=%.2f net=%.2f",
                        g_session_id, deal_ticket, MinuteStrLocal(ToLocal(deal_time)),
                        p, comm, swap, net);
         }
      }

      Sleep(InpLateProfitRetrySeconds * 1000);

      // Ponownie wybieramy historię z tym samym FROM ale przesuniętym TO,
      // bo DEAL_PROFIT bywa aktualizowany chwilę po zamknięciu pozycji.
      datetime to_server_retry = TimeCurrent();
      if(!HistorySelect(from_server, to_server_retry))
      {
         PrintFormat("ProcessCloseDeals: retry HistorySelect failed err=%d", GetLastError());
      }
      else
      {
         int total_retry = HistoryDealsTotal();
         double session_total_profit_retry = 0.0;

         for(int i = 0; i < total_retry; i++)
         {
            ulong deal_ticket = HistoryDealGetTicket(i);
            if(deal_ticket == 0)
               continue;

            long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
               continue;

            string sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            if(InpSymbolFilter != "" && sym != InpSymbolFilter)
               continue;

            long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
            if(InpMagicFilter != -1 && magic != InpMagicFilter)
               continue;

            double p_retry = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            if(p_retry == 0.0)
               continue;

            long deal_time_msc_retry = (long)HistoryDealGetInteger(deal_ticket, DEAL_TIME_MSC);

            // ANTI‑DUPLICATE jak w pierwszym skanie
            if(deal_ticket <= g_last_deal_ticket_logged &&
               deal_time_msc_retry <= g_last_deal_time_msc_logged)
               continue;
            if(deal_ticket <= g_last_deal_ticket_logged)
               continue;

            session_total_profit_retry += p_retry;
         }

         PrintFormat("ProcessCloseDeals: retry finished session_id=%d total_profit_only_retry=%.2f (old=%.2f)",
                     g_session_id, session_total_profit_retry, session_total_profit);

         // Aktualizujemy wynik do LogDealPerAccount/LogDealDetail dla tego domknięcia sesji.
         session_total_profit = session_total_profit_retry;
         to_server = to_server_retry;
         total = total_retry;
      }
   }

   // ---------------------------------------------------------
   // 2) DRUGIE PRZEJŚCIE: logujemy każdy deal z tego samego zakresu
   // ---------------------------------------------------------
   for(int i = 0; i < total; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      long deal_type = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      long entry     = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;

      string sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
      if(InpSymbolFilter != "" && sym != InpSymbolFilter)
         continue;

      long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(InpMagicFilter != -1 && magic != InpMagicFilter)
         continue;

      double p = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      if(p == 0.0)
         continue;

      long     deal_time_msc = (long)HistoryDealGetInteger(deal_ticket, DEAL_TIME_MSC);
      datetime deal_time     = (datetime)(deal_time_msc / 1000);

      if(deal_ticket <= g_last_deal_ticket_logged &&
         deal_time_msc <= g_last_deal_time_msc_logged)
         continue;

      if(deal_ticket <= g_last_deal_ticket_logged)
         continue;

      ulong    pos_id    = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
      datetime open_time = FindOpenTimeByPositionId(pos_id, from_server, to_server);
      if(open_time == 0)
         open_time = deal_time;

      double profit_only = p;

      // Account Age Report – licznik dni z handlem (czas lokalny dnia)
      datetime day_local = DayStartLocal(ToLocal(deal_time));
      if(day_local != g_last_trade_day)
      {
         g_active_trading_days++;
         g_last_trade_day = day_local;
      }

      // Account Age Report – łączny czas trwania transakcji (sekundy)
      if(open_time > 0 && deal_time >= open_time)
         g_total_trade_duration_sec += (double)(deal_time - open_time);

      // --- DIAGNOSTYKA + aktualizacja sesyjnych i okresowych statystyk profit/loss ---
      if(profit_only > 0.0)
      {
         // Sesyjny profit dodatni
         g_session_profit_pos += profit_only;
         Print("DEBUG ADD pos: ticket=", deal_ticket, 
               " profit=", profit_only, 
               " new pos=", g_session_profit_pos);

         // Account Age – suma profitów dodatnich i liczba wygranych
         g_sum_profit += profit_only;
         g_win_trades++;

         // Account Age – serie wygranych
         g_consecutive_wins++;
         if(g_consecutive_wins > g_max_consecutive_wins)
            g_max_consecutive_wins = g_consecutive_wins;
         g_consecutive_losses = 0;
      }
      else if(profit_only < 0.0)
      {
         // Sesyjny profit ujemny
         g_session_profit_neg += profit_only;
         Print("DEBUG ADD neg: ticket=", deal_ticket, 
               " profit=", profit_only, 
               " new neg=", g_session_profit_neg);

         // Account Age – suma strat (wartość dodatnia)
         g_sum_loss += MathAbs(profit_only);

         // Account Age – serie strat
         g_consecutive_losses++;
         if(g_consecutive_losses > g_max_consecutive_losses)
            g_max_consecutive_losses = g_consecutive_losses;
         g_consecutive_wins = 0;
      }

      // Account Age – liczba wszystkich transakcji w okresie
      if(profit_only != 0.0)
         g_total_trades++;

      LogDealDetail(deal_ticket, open_time, deal_time, p);

      // tu max_session_profit = session_total_profit z tej SESJI (nie z całego dnia)
      LogDealPerAccount(deal_ticket, g_session_id, session_total_profit);

      g_last_deal_ticket_logged   = deal_ticket;
      g_last_deal_time_msc_logged = deal_time_msc;
   }
}
//+------------------------------------------------------------------+
//| Expert init                                                      |
//+------------------------------------------------------------------+
int OnInit()
{

   // konto MT5
   g_login = (ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   g_is_live_account = IsLiveProductionAccount(g_login, AccountInfoString(ACCOUNT_SERVER));
   Print("Account mode detection: login=",(string)g_login,
         " server=", AccountInfoString(ACCOUNT_SERVER),
         " live=", (g_is_live_account ? "true" : "false"));

   // GLOBALNY plik dzienny – jedna nazwa z inputu
   g_daily_file = InpDailyFile;   // "DailySessionSummary.csv"

   datetime now = NowTime();
   g_day_start         = DayStart(now);
   g_start_balance_day = AccountInfoDouble(ACCOUNT_BALANCE);

   // upewnij się, że każdy typ pliku ma swój nagłówek
   EnsureHeaderDaily();   // globalny DailySessionSummary.csv (15 kolumn, w tym minuty)
   EnsureHeaderDeals();   // DAILY_ACCOUNTSDETAILS.csv
   EnsureHeaderThresh();  // SessionDD_Thresholds.csv
   // EnsureHeaderDailyGlobal();  // TEGO JUŻ NIE WYWOŁUJEMY

   // Flush pending zapisów z kolejki (gdy pliki były zablokowane przez Excela).
   // To przywraca ciągłość logowania bez duplikacji (enqueue dopisuje wiersze, a flush kasuje kolejkę).
   string perfile = StringFormat("DailySessionDeals%I64u.csv", g_login);
   EnsureHeaderDailyDealsPerAccount(perfile);
   FlushPendingWriteQueues();

   // start dnia wg lokalnego czasu
   ResetDay(DayStartLocal(NowTime()));

   // timer
   EventSetTimer(InpTimerSeconds);

   // ------------------------------------------------------
   // Account Age Report — wznowienie okresu po restarcie EA (sidecar + opcjonalnie hydrate z CSV)
   // ------------------------------------------------------
   bool resumed_account_age = false;
   if(LoadAccountAgeSidecar(g_login))
   {
      g_account_age_reported = false;
      HydrateAccountAgeFromCsv(g_account_period_uid, g_login);
      resumed_account_age = true;
      Print("OnInit AccountAge: WZNOWIONO okres z pliku .state uid=", g_account_period_uid,
            " start_server=", TimeToString(g_account_start_time, TIME_DATE | TIME_MINUTES));
   }

   if(!resumed_account_age && g_account_start_time == 0)
   {
      // Nowy okres: pierwszy start EA albo po FAIL (brak pliku .state)
      g_account_start_time    = TimeCurrent(); // czas serwerowy
      g_account_period_uid    = (string)g_login + "_" + (string)((long)g_account_start_time);
      g_account_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_account_max_equity    = g_account_start_balance;

      g_active_trading_days        = 0;
      g_last_trade_day             = 0;
      g_total_trades               = 0;
      g_win_trades                 = 0;
      g_sum_profit                 = 0.0;
      g_sum_loss                   = 0.0;
      g_consecutive_wins           = 0;
      g_max_consecutive_wins       = 0;
      g_consecutive_losses         = 0;
      g_max_consecutive_losses     = 0;
      g_total_trade_duration_sec   = 0.0;
      g_total_sessions             = 0;
      g_account_age_reported       = false;
      Print("OnInit AccountAge: NOWY okres (brak sidecar) uid=", g_account_period_uid);
   }

   if(!g_account_age_reported && g_account_period_uid != "" && g_account_start_time > 0)
      SaveAccountAgeSidecar();

   Print("DailySessionLogger_v2 started. login=",(string)g_login,
         " files in Common\\Files: ", g_daily_file,
         ", ", InpDealsFile,
         ", ", InpThreshFile);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime now = NowTime();
   datetime ds  = DayStartLocal(now);

   // day rollover: finalize any active session first
   if(ds != g_day_start)
{
   AppendDailyFinalRow();  // zapis stanu na koniec dnia

   ResetDay(ds);
   return;
}

   // normal cycle
   UpdateSessionMetrics();

   // Okresowo próbuj flusha pending queue (gdy Excel właśnie zwolnił blokadę).
   g_pending_flush_counter += InpTimerSeconds;
   if(g_pending_flush_counter >= g_pending_flush_period_seconds)
   {
      g_pending_flush_counter = 0;
      FlushPendingWriteQueues();
   }

   // Wykrywanie RESET balansu (Balance Operation) – core trigger nowego okresu życia konta
   // Uwaga: to jest JEDYNE miejsce, które ma prawo wywołać HandleBalanceReset()
   DetectAndHandleBalanceReset();

   //ProcessCloseDeals();   // tu ewentualnie wykryjesz DEAL_REASON_SO i IsBalanceResetDeal()

   // FAIL: jeżeli equity albo balance < 1000 w dowolnym momencie dnia
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(eq < 1000.0 || bal < 1000.0)
      g_day_failed = true;          // TYLKO FAIL, nie reset

   // live-update co g_live_update_period sekund
   g_live_update_counter += InpTimerSeconds;
   if(g_live_update_counter >= g_live_update_period)
   {
      g_live_update_counter = 0;
   }
}

//+------------------------------------------------------------------+
//| Expert deinit — zapis stanu Account Age przed odlączeniem EA     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!g_account_age_reported && g_account_period_uid != "" && g_account_start_time > 0)
      SaveAccountAgeSidecar();
}
