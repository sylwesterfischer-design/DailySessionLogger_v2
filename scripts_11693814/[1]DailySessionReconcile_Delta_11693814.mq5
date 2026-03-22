#property strict
#property script_show_inputs

// Stage A (RECONCILED inputs) — konto 11693814, domyslnie dzien 19.03.2026:
// - nie modyfikuje produkcyjnych CSV
// - tworzy pliki:
//   * DailySessionDeals11693814_RECONCILED.csv
//   * DailySessionSummary_RECONCILED_11693814_<dd-mm-yyyy>.csv
//   * DailySessionReconcile_MT5_CHECK_11693814_<dd-mm-yyyy>.txt (agregaty z historii do porownania z raportem)
//
// Uwaga: w tej wersji start_balance/end_balance dla sesji liczymy z poprawionej "ciągłości"
// na podstawie:
// - source DailySessionSummary.csv (max_session_profit)
// - poprawnej bazy: last end_balance z poprzedniego dnia (prev day last session)
//
// Ten plik ma po prostu odblokowac pipeline A->B->C, gdy pełna wersja Stage-A
// była pusta/utracona.
//
// Wersja pliku (kompilacja MT5): 2026-03-13 — MT5_CHECK + ACCOUNT_LOGIN + audyt pliku deals (FNV/mtime)
// + DIAG: liczniki deals/summary w Print i w MT5_CHECK (0 danych = widoczny powod).

input ulong  InpLogin   = 11693814;
input string InpDateTag = "19-03-2026"; // dd-mm-yyyy (zgodne z Flush script)
input bool   InpDryRun   = false;      // true => nie pisz plikow
input bool   InpAbortIfReconciledSummaryExists = false; // true = nie nadpisuj istniejącego *_RECONCILED_<data>.csv (tylko log + exit 6)

// Identyfikator wersji raportu MT5_CHECK (odtwarzalnosc audytu; zmien przy kolejnych modyfikacjach skryptu).
const string RECONCILE_SCRIPT_VERSION = "2026-03-13-MT5AUDIT4-SUMMARYGUARD";

// --- Diagnostyka przebiegu (Print + MT5_CHECK) — nie zmienia logiki Stage A, tylko observability ---
string g_diag_deals_src = "";
bool   g_diag_deals_read_ok = false;
ulong  g_diag_deals_strlen = 0;
int    g_diag_deals_total_lines = 0;
int    g_diag_deals_data_rows_guess = 0;
string g_diag_deals_head_preview = "";
string g_diag_deals_fail_reason = "";

int    g_diag_sum_file_lines = 0;
int    g_diag_sum_rows_parse_ok = 0;
int    g_diag_sum_rows_date_match = 0;
int    g_diag_sum_rows_konto_match = 0;
string g_diag_summary_fail_reason = "";
int    g_diag_summary_sessions_loaded = 0;

string g_diag_summary_target_iso = "";
bool   g_diag_prev_day_ok = false;
double g_diag_prev_day_end_balance = 0.0;
string g_diag_prev_iso_date = "";

int    g_diag_exit_code = 0;
string g_diag_exit_detail = "";

// -------------------- helpers --------------------
string TrimSpaces(string s)
{
   int i0 = 0;
   int i1 = StringLen(s) - 1;
   while(i0 <= i1 && (s[i0] == ' ' || s[i0] == '\t' || s[i0] == '\r' || s[i0] == '\n')) i0++;
   while(i1 >= i0 && (s[i1] == ' ' || s[i1] == '\t' || s[i1] == '\r' || s[i1] == '\n')) i1--;
   if(i1 < i0) return "";
   return StringSubstr(s, i0, i1 - i0 + 1);
}

// dd-mm-yyyy => yyyy-mm-dd
string IsoDateFromTag(const string tag)
{
   string parts[];
   int n = StringSplit(tag, '-', parts);
   if(n != 3) return "";
   int day  = (int)StringToInteger(parts[0]);
   int mon  = (int)StringToInteger(parts[1]);
   int year = (int)StringToInteger(parts[2]);
   return StringFormat("%04d-%02d-%02d", year, mon, day);
}

datetime DatetimeFromIsoDateAtMidnight(const string iso_date)
{
   // yyyy-mm-dd => datetime (lokalny midnight)
   string parts[];
   int n = StringSplit(iso_date, '-', parts);
   if(n != 3) return 0;

   MqlDateTime dt;
   dt.year = (int)StringToInteger(parts[0]);
   dt.mon  = (int)StringToInteger(parts[1]);
   dt.day  = (int)StringToInteger(parts[2]);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

string DateStr(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
}

string NumStr(double v, int digits)
{
   // Mamy w CSV przecinek jako separator.
   string s = DoubleToString(v, digits);
   // StringReplace zwraca int (liczba zamian) i modyfikuje string przez referencje.
   StringReplace(s, ".", ",");
   return s;
}

// Parse "123,45" => 123.45
double ParseDoubleComma(const string token)
{
   string s = TrimSpaces(token);
   if(s == "") return 0.0;

   // Usun apostrof (jak w session_id w summary bywa "'0")
   if(StringLen(s) > 0 && (uchar)s[0] == 39)
      s = StringSubstr(s, 1);

   s = TrimSpaces(s);
   // Usun % (jesli kiedys trafilby np. "12,34%")
   StringReplace(s, "%", "");
   StringReplace(s, ".", "");
   StringReplace(s, ",", ".");
   return StringToDouble(s);
}

ulong ParseULongSimple(const string token)
{
   string s = TrimSpaces(token);
   if(StringLen(s) > 0 && (uchar)s[0] == 39) // apostrophe
      s = StringSubstr(s, 1);
   if(s == "") return 0;
   return (ulong)StringToInteger(s);
}

string BuildCsvLine(string &cols[], int sz)
{
   // Budujemy wiersz z cytowaniem gdy potrzeba.
   string line = "";
   for(int i = 0; i < sz; i++)
   {
      string v = cols[i];
      bool need_quotes =
         (StringFind(v, ";")  >= 0) ||
         (StringFind(v, "\"") >= 0) ||
         (StringFind(v, "\n") >= 0) ||
         (StringFind(v, "\r") >= 0);

      if(need_quotes)
      {
         StringReplace(v, "\"", "\"\"");
         v = StringFormat("\"%s\"", v);
      }

      if(i > 0)
         line += ";";
      line += v;
   }
   return line;
}

bool ReadFileCommonToString(const string filename, string &out)
{
   out = "";
   int h = FileOpen(filename, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
      return false;

   ulong sz = FileSize(h);
   if(sz > 0)
      out = FileReadString(h, (int)sz);
   FileClose(h);
   return true;
}

bool WriteFileCommonFromString(const string filename, const string content)
{
   if(InpDryRun)
   {
      Print("DryRun=true: skip write filename=", filename);
      return true;
   }

   int h = FileOpen(filename, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("Cannot open for write filename=", filename, " err=", GetLastError());
      return false;
   }
   if(content != "")
      FileWriteString(h, content);
   FileClose(h);
   return true;
}

bool EnsureOutputDealsCopy(const string source_deals, const string out_deals)
{
   // Zbierz statystyki pliku deals (COMMON) — gdy 0 wierszy danych, widac to w MT5_CHECK i w Experts.
   string content = "";
   g_diag_deals_src = source_deals;
   g_diag_deals_fail_reason = "";
   g_diag_deals_read_ok = ReadFileCommonToString(source_deals, content);
   g_diag_deals_strlen = (ulong)StringLen(content);
   g_diag_deals_total_lines = 0;
   g_diag_deals_data_rows_guess = 0;
   g_diag_deals_head_preview = "";

   if(!g_diag_deals_read_ok)
   {
      int err = GetLastError();
      g_diag_deals_fail_reason = "DEALS_READ_FAIL_err_" + IntegerToString(err);
      Print("DIAG deals: cannot read file=", source_deals, " err=", err, " (sprawdz COMMON i nazwe pliku)");
      Print("StageA: cannot read source deals=", source_deals, " err=", err);
      return false;
   }

   // Normalizacja EOL do liczenia wierszy (jak w pozostalych parserach).
   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");
   string dlines[];
   int dn = StringSplit(content, '\n', dlines);
   g_diag_deals_total_lines = dn;

   int data_rows = 0;
   for(int di = 0; di < dn; di++)
   {
      string ln = TrimSpaces(dlines[di]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0)
      {
         if(g_diag_deals_head_preview == "")
            g_diag_deals_head_preview = StringSubstr(ln, 0, 220);
         continue;
      }
      data_rows++;
   }
   g_diag_deals_data_rows_guess = data_rows;

   Print("DIAG deals: file=", source_deals, " strlen=", (string)g_diag_deals_strlen,
         " lines_total=", g_diag_deals_total_lines, " data_rows_guess=", g_diag_deals_data_rows_guess);

   if(content == "")
   {
      g_diag_deals_fail_reason = "DEALS_EMPTY_CONTENT_AFTER_READ";
      Print("DIAG deals: zrodlo puste (0 znakow) — EA nie zapisal lub zly plik w COMMON.");
      Print("StageA: source deals empty=", source_deals);
      return false;
   }

   if(g_diag_deals_data_rows_guess == 0 && g_diag_deals_head_preview == "")
      Print("DIAG deals: UWAGA — brak naglowka date;konto;session_id; sprawdz format CSV w COMMON.");

   Print("StageA: writing deals reconciled copy => ", out_deals);
   return WriteFileCommonFromString(out_deals, content);
}

// -------------------- schema keys --------------------
string ReconciledDealsFilename()
{
   return StringFormat("DailySessionDeals%I64u_RECONCILED.csv", InpLogin);
}

string ReconciledSummaryFilename()
{
   return StringFormat("DailySessionSummary_RECONCILED_%I64u_%s.csv", InpLogin, InpDateTag);
}

string SourceDealsFilename()
{
   return StringFormat("DailySessionDeals%I64u.csv", InpLogin);
}

// 16 znakow hex (FNV-1a 64-bit) — odcisk zawartosci pliku w COMMON.
string Hex64Ulong(ulong v)
{
   const string HEX = "0123456789ABCDEF";
   string s = "";
   for(int i = 0; i < 16; i++)
   {
      int shift = (15 - i) * 4;
      ulong nibble = (v >> shift) & 0x0F;
      int idx = (int)nibble;
      s += StringSubstr(HEX, idx, 1);
   }
   return s;
}

// FNV-1a 64-bit na calym pliku (FILE_COMMON|FILE_BIN) + rozmiar i FILE_MODIFY_DATE — audyt zrodla deals.
bool Fnv1aHashCommonFile(const string fname, ulong &out_hash, ulong &out_size, datetime &out_mtime, string &out_err)
{
   out_err = "";
   out_hash = 0;
   out_size = 0;
   out_mtime = 0;
   int h = FileOpen(fname, FILE_READ | FILE_COMMON | FILE_BIN);
   if(h == INVALID_HANDLE)
   {
      out_err = "FileOpen_fail_" + IntegerToString(GetLastError());
      return false;
   }
   out_size = FileSize(h);
   out_mtime = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
   // Stale FNV-1a 64-bit (hex 0xCBF29CE484222325 / 0x100000001B3).
   const ulong FNV64_OFFSET = 0xCBF29CE484222325;
   const ulong FNV64_PRIME = 0x100000001B3;
   ulong h64 = FNV64_OFFSET;
   uchar buf[];
   const int CHUNK = 16384;
   ArrayResize(buf, CHUNK);
   FileSeek(h, 0, SEEK_SET);
   for(;;)
   {
      uint r = FileReadArray(h, buf, 0, CHUNK);
      if(r == 0) break;
      for(uint i = 0; i < r; i++)
      {
         h64 ^= (ulong)buf[i];
         h64 *= FNV64_PRIME;
      }
   }
   FileClose(h);
   out_hash = h64;
   return true;
}

string SourceSummaryFilename()
{
   return "DailySessionSummary.csv";
}

// -------------------- core parsing --------------------
struct SessOut
{
   ulong   session_id;
   double  session_net;               // source max_session_profit (numeric)
   string  col5_max_session_equity_drawdown; // as-is from source (string)
   string  col6_max_session_profit;         // as-is from source (string)
   string  col7_max_single_lot;              // as-is
   string  col8_max_total_lot;               // as-is
   string  col9_max_margin_burned;           // as-is (with %)
   string  col10_max_equity_burned_percent;  // as-is (with %)
   string  col11_account_reset;             // as-is
   string  col12_minute_session_start;     // as-is
   string  col13_minute_session_end;       // as-is
};

int FindSessOutIndex(SessOut &arr[], ulong sid)
{
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i].session_id == sid)
         return i;
   return -1;
}

bool LoadSourceSessionsForDate(const string source_summary, const string target_iso_date,
                               SessOut &out_sessions[], ulong &out_first_sid, ulong &out_min_sid,
                               double &out_source_start_balance_for_min_sid)
{
   ArrayResize(out_sessions, 0);
   out_first_sid = 0;
   out_min_sid   = 0;
   out_source_start_balance_for_min_sid = 0.0;

   // Liczniki do MT5_CHECK — dlaczego 0 sesji (zla data vs brak konto vs pusty plik).
   g_diag_sum_file_lines = 0;
   g_diag_sum_rows_parse_ok = 0;
   g_diag_sum_rows_date_match = 0;
   g_diag_sum_rows_konto_match = 0;
   g_diag_summary_fail_reason = "";
   g_diag_summary_sessions_loaded = 0;

   string content = "";
   if(!ReadFileCommonToString(source_summary, content))
   {
      int err = GetLastError();
      g_diag_summary_fail_reason = "SUMMARY_READ_FAIL_err_" + IntegerToString(err);
      Print("StageA: cannot read source summary=", source_summary, " err=", err);
      return false;
   }
   if(content == "")
   {
      g_diag_summary_fail_reason = "SOURCE_SUMMARY_EMPTY";
      Print("StageA: source summary empty=", source_summary);
      return false;
   }

   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");
   string lines[];
   int n = StringSplit(content, '\n', lines);
   g_diag_sum_file_lines = n;

   bool any = false;
   for(int li = 0; li < n; li++)
   {
      string ln = TrimSpaces(lines[li]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0) continue;

      string cols[];
      int cn = StringSplit(ln, ';', cols);
      if(cn < 14) continue;

      g_diag_sum_rows_parse_ok++;

      string date_str = TrimSpaces(cols[0]);
      ulong konto = ParseULongSimple(cols[1]);
      if(date_str != target_iso_date) continue;
      g_diag_sum_rows_date_match++;
      if(konto != InpLogin) continue;
      g_diag_sum_rows_konto_match++;

      ulong sid = ParseULongSimple(cols[2]);

      int idx = FindSessOutIndex(out_sessions, sid);
      if(idx < 0)
      {
         int k = ArraySize(out_sessions);
         ArrayResize(out_sessions, k + 1);
         out_sessions[k].session_id = sid;

         // --- Store all non-start/end columns as-is from source ---
         out_sessions[k].session_net = ParseDoubleComma(cols[6]); // max_session_profit numeric
         out_sessions[k].col5_max_session_equity_drawdown = TrimSpaces(cols[5]);
         out_sessions[k].col6_max_session_profit = TrimSpaces(cols[6]);
         out_sessions[k].col7_max_single_lot = TrimSpaces(cols[7]);
         out_sessions[k].col8_max_total_lot = TrimSpaces(cols[8]);
         out_sessions[k].col9_max_margin_burned = TrimSpaces(cols[9]);
         out_sessions[k].col10_max_equity_burned_percent = TrimSpaces(cols[10]);
         out_sessions[k].col11_account_reset = TrimSpaces(cols[11]);
         out_sessions[k].col12_minute_session_start = TrimSpaces(cols[12]);
         out_sessions[k].col13_minute_session_end = TrimSpaces(cols[13]);

         // Track min sid + its source start_balance (col3) for fallback.
         if(!any || sid < out_min_sid)
         {
            out_min_sid = sid;
            out_source_start_balance_for_min_sid = ParseDoubleComma(cols[3]);
         }

         any = true;
      }
      else
      {
         // Anti-duplicate: keep last occurrence.
         out_sessions[idx].session_net = ParseDoubleComma(cols[6]);
         out_sessions[idx].col5_max_session_equity_drawdown = TrimSpaces(cols[5]);
         out_sessions[idx].col6_max_session_profit = TrimSpaces(cols[6]);
         out_sessions[idx].col7_max_single_lot = TrimSpaces(cols[7]);
         out_sessions[idx].col8_max_total_lot = TrimSpaces(cols[8]);
         out_sessions[idx].col9_max_margin_burned = TrimSpaces(cols[9]);
         out_sessions[idx].col10_max_equity_burned_percent = TrimSpaces(cols[10]);
         out_sessions[idx].col11_account_reset = TrimSpaces(cols[11]);
         out_sessions[idx].col12_minute_session_start = TrimSpaces(cols[12]);
         out_sessions[idx].col13_minute_session_end = TrimSpaces(cols[13]);
      }
   }

   out_first_sid = (any ? out_sessions[0].session_id : 0);
   if(!any)
   {
      g_diag_summary_fail_reason = "NO_SESSIONS_FOR_DATE_AND_LOGIN";
      Print("DIAG summary: plik=", source_summary, " lines_file=", g_diag_sum_file_lines,
            " rows_14cols=", g_diag_sum_rows_parse_ok,
            " date_match=", g_diag_sum_rows_date_match, " (target=", target_iso_date, ")",
            " konto_match=", g_diag_sum_rows_konto_match, " (InpLogin=", InpLogin, ")");
      Print("StageA: no sessions found in source summary for date=", target_iso_date, " konto=", InpLogin);
      return false;
   }
   g_diag_summary_sessions_loaded = ArraySize(out_sessions);
   Print("DIAG summary: sessions_loaded=", g_diag_summary_sessions_loaded,
         " (wiersze z date+konto dla tego dnia)");
   return true;
}

void SortSessionsBySid(SessOut &arr[])
{
   // Proste sortowanie bąbelkowe po session_id (mały zakres).
   for(int i = 0; i < ArraySize(arr); i++)
   {
      for(int j = i + 1; j < ArraySize(arr); j++)
      {
         if(arr[j].session_id < arr[i].session_id)
         {
            SessOut tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
         }
      }
   }
}

bool LoadPrevDayLastEndBalance(const string source_summary, const string prev_iso_date, double &out_prev_end_balance)
{
   out_prev_end_balance = 0.0;
   ulong best_sid = 0;
   bool  have_best = false;

   string content = "";
   if(!ReadFileCommonToString(source_summary, content))
   {
      Print("StageA: cannot read source summary for prev day=", source_summary, " err=", GetLastError());
      return false;
   }
   if(content == "")
      return false;

   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");

   string lines[];
   int n = StringSplit(content, '\n', lines);
   bool any = false;

   for(int li = 0; li < n; li++)
   {
      string ln = TrimSpaces(lines[li]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0) continue;

      string cols[];
      int cn = StringSplit(ln, ';', cols);
      if(cn < 14) continue;

      string date_str = TrimSpaces(cols[0]);
      ulong konto = ParseULongSimple(cols[1]);
      if(date_str != prev_iso_date) continue;
      if(konto != InpLogin) continue;

      ulong sid = ParseULongSimple(cols[2]);
      double end_balance = ParseDoubleComma(cols[4]);

      // Największy session_id z prev day => "ostatnia sesja".
      if(!have_best || sid >= best_sid)
      {
         best_sid = sid;
         out_prev_end_balance = end_balance;
         any = true;
         have_best = true;
      }
   }

   return any;
}

bool WriteReconciledSummary(const string dest_summary_file, const string target_iso_date, SessOut &sessions[],
                             double start_balance_for_first_session)
{
   if(InpDryRun)
   {
      Print("DryRun=true: skip writing reconciled summary => ", dest_summary_file);
      return true;
   }

   // Wymazujemy i piszemy od nowa.
   int h = FileOpen(dest_summary_file, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("StageA: cannot open reconciled summary for write=", dest_summary_file, " err=", GetLastError());
      return false;
   }

   FileWriteString(h, "sep=;\r\n");

   string expected_header =
      "date;konto;session_id;"
      "start_balance;end_balance;"
      "max_session_equity_drawdown;max_session_profit;"
      "max_single_lot;max_total_lot;"
      "max_margin_burned;max_session_equity_burned_percent;account_reset;"
      "minute_session_start;minute_session_end";

   FileWriteString(h, expected_header + "\r\n");

   double computed_start = start_balance_for_first_session;
   for(int i = 0; i < ArraySize(sessions); i++)
   {
      double computed_end = computed_start + sessions[i].session_net;

      // --- grow[14] w kolejnosci schema DailySessionSummary.csv ---
      string cols[14];
      cols[0]  = target_iso_date;
      cols[1]  = (string)InpLogin;
      cols[2]  = "'" + (string)sessions[i].session_id;
      cols[3]  = NumStr(computed_start, 2);  // start_balance
      cols[4]  = NumStr(computed_end, 2);    // end_balance
      cols[5]  = sessions[i].col5_max_session_equity_drawdown;
      cols[6]  = sessions[i].col6_max_session_profit;
      cols[7]  = sessions[i].col7_max_single_lot;
      cols[8]  = sessions[i].col8_max_total_lot;
      cols[9]  = sessions[i].col9_max_margin_burned;
      cols[10] = sessions[i].col10_max_equity_burned_percent;
      cols[11] = sessions[i].col11_account_reset;
      cols[12] = sessions[i].col12_minute_session_start;
      cols[13] = sessions[i].col13_minute_session_end;

      // Zapisujemy bez dodatkowego quotowania (to jest juz zgodne z source).
      for(int ci = 0; ci < 14; ci++)
      {
         if(ci > 0) FileWriteString(h, ";");
         FileWriteString(h, cols[ci]);
      }
      FileWriteString(h, "\r\n");

      computed_start = computed_end;
   }

   FileClose(h);

   Print("StageA: reconciled summary written => ", dest_summary_file,
         " sessions=", ArraySize(sessions),
         " start_balance_first=", NumStr(start_balance_for_first_session, 2));
   return true;
}

// Jedna doba kalendarzowa (czas lokalny MT5) dla InpDateTag — do HistorySelect.
bool HistoryBoundsForDateTag(const string tag, datetime &out_from, datetime &out_to)
{
   string iso = IsoDateFromTag(tag);
   if(iso == "") return false;
   string parts[];
   if(StringSplit(iso, '-', parts) != 3) return false;
   int y = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   int d = (int)StringToInteger(parts[2]);
   string s0 = StringFormat("%04d.%02d.%02d 00:00", y, m, d);
   string s1 = StringFormat("%04d.%02d.%02d 23:59:59", y, m, d);
   out_from = StringToTime(s0);
   out_to   = StringToTime(s1);
   return (out_from > 0 && out_to > 0);
}

// Agregaty z historii + diagnostyka Stage A w jednym pliku MT5_CHECK (pisany na koniec OnStart).
void WriteMt5CheckReportFull()
{
   string date_tag = InpDateTag;
   datetime hf = 0, ht = 0;
   bool ok_bounds = HistoryBoundsForDateTag(date_tag, hf, ht);
   if(!ok_bounds)
      Print("MT5_CHECK: bad date_tag=", date_tag);

   int hist_err = 0;
   bool ok_hist = false;
   if(ok_bounds)
   {
      ok_hist = HistorySelect(hf, ht);
      if(!ok_hist)
         hist_err = GetLastError();
   }

   int total = 0;
   if(ok_hist)
      total = HistoryDealsTotal();

   double sum_profit = 0.0;
   double sum_swap = 0.0;
   double sum_comm = 0.0;
   double sum_fee = 0.0;
   int cnt_exit = 0;
   if(ok_hist)
   {
      for(int i = 0; i < total; i++)
      {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0) continue;
         long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         long typ = HistoryDealGetInteger(tk, DEAL_TYPE);
         if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL) continue;
         datetime tdeal = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
         if(tdeal < hf || tdeal > ht) continue;
         sum_profit += HistoryDealGetDouble(tk, DEAL_PROFIT);
         sum_swap += HistoryDealGetDouble(tk, DEAL_SWAP);
         sum_comm += HistoryDealGetDouble(tk, DEAL_COMMISSION);
         sum_fee += HistoryDealGetDouble(tk, DEAL_FEE);
         cnt_exit++;
      }
   }

   string fn = StringFormat("DailySessionReconcile_MT5_CHECK_%I64u_%s.txt", InpLogin, date_tag);
   string body = "";
   body += "MT5_HISTORY_CHECK (porownanie z raportem / eksportem z terminala)\r\n";
   body += "script=DailySessionReconcile_Delta\r\n";
   body += "expected_login=" + (string)InpLogin + "\r\n";
   body += "terminal_login=" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "\r\n";
   body += "date_tag=" + date_tag + "\r\n";
   body += "history_bounds_ok=" + (ok_bounds ? "1" : "0") + "\r\n";
   if(ok_bounds)
   {
      body += "history_from=" + TimeToString(hf, TIME_DATE|TIME_MINUTES) + "\r\n";
      body += "history_to=" + TimeToString(ht, TIME_DATE|TIME_MINUTES) + "\r\n";
   }
   body += "history_select_ok=" + (ok_hist ? "1" : "0") + "\r\n";
   if(!ok_hist && ok_bounds)
      body += "history_select_err=" + IntegerToString(hist_err) + "\r\n";

   body += "exit_deals_count=" + IntegerToString(cnt_exit) + "\r\n";
   body += "sum_deal_profit_only=" + NumStr(sum_profit, 2) + "\r\n";
   body += "sum_deal_swap=" + NumStr(sum_swap, 2) + "\r\n";
   body += "sum_deal_commission=" + NumStr(sum_comm, 2) + "\r\n";
   body += "sum_deal_fee=" + NumStr(sum_fee, 2) + "\r\n";
   body += "sum_net_pl=" + NumStr(sum_profit + sum_swap + sum_comm + sum_fee, 2) + "\r\n";

   // Sekcja STAGE_DIAG: odpowiedz na pytanie „skad 0 wierszy” bez zgadywania.
   body += "--- STAGE_DIAG (czemu 0 danych / exit) ---\r\n";
   body += "dry_run=" + (InpDryRun ? "1" : "0") + "\r\n";
   body += "stage_exit_code=" + IntegerToString(g_diag_exit_code) + "\r\n";
   body += "stage_exit_detail=" + g_diag_exit_detail + "\r\n";
   body += "target_iso_date=" + g_diag_summary_target_iso + "\r\n";
   body += "summary_fail_reason=" + g_diag_summary_fail_reason + "\r\n";
   body += "deals_source_file=" + g_diag_deals_src + "\r\n";
   body += "deals_read_ok=" + (g_diag_deals_read_ok ? "1" : "0") + "\r\n";
   body += "deals_strlen=" + (string)g_diag_deals_strlen + "\r\n";
   body += "deals_total_lines=" + IntegerToString(g_diag_deals_total_lines) + "\r\n";
   body += "deals_data_rows_guess=" + IntegerToString(g_diag_deals_data_rows_guess) + "\r\n";
   body += "deals_header_preview=" + g_diag_deals_head_preview + "\r\n";
   body += "deals_fail_reason=" + g_diag_deals_fail_reason + "\r\n";
   body += "summary_file_lines=" + IntegerToString(g_diag_sum_file_lines) + "\r\n";
   body += "summary_rows_14cols=" + IntegerToString(g_diag_sum_rows_parse_ok) + "\r\n";
   body += "summary_rows_date_match=" + IntegerToString(g_diag_sum_rows_date_match) + "\r\n";
   body += "summary_rows_konto_match=" + IntegerToString(g_diag_sum_rows_konto_match) + "\r\n";
   body += "summary_sessions_loaded=" + IntegerToString(g_diag_summary_sessions_loaded) + "\r\n";
   body += "prev_day_iso=" + g_diag_prev_iso_date + "\r\n";
   body += "prev_day_end_balance_ok=" + (g_diag_prev_day_ok ? "1" : "0") + "\r\n";
   body += "prev_day_end_balance=" + NumStr(g_diag_prev_day_end_balance, 2) + "\r\n";

   string deals_src = SourceDealsFilename();
   ulong fnv = 0, fsz = 0;
   datetime fmt = 0;
   string ferr = "";
   bool ok_f = Fnv1aHashCommonFile(deals_src, fnv, fsz, fmt, ferr);
   body += "reconcile_script_version=" + RECONCILE_SCRIPT_VERSION + "\r\n";
   body += "source_deals_csv=" + deals_src + "\r\n";
   if(ok_f)
   {
      body += "source_deals_size_bytes=" + (string)fsz + "\r\n";
      body += "source_deals_mtime=" + TimeToString(fmt, TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\r\n";
      body += "source_deals_fnv1a64_hex=" + Hex64Ulong(fnv) + "\r\n";
   }
   else
   {
      body += "source_deals_size_bytes=0\r\n";
      body += "source_deals_mtime=NA\r\n";
      body += "source_deals_fnv1a64_hex=NA\r\n";
      body += "source_deals_audit_err=" + ferr + "\r\n";
   }
   body += "Uwaga: EA w CSV loguje DEAL_PROFIT (profit_only) per deal — sumy moga roznic sie od raportu net.\r\n";

   if(!WriteFileCommonFromString(fn, body))
      Print("MT5_CHECK: cannot write file=", fn);
   else
      Print("MT5_CHECK: ver=", RECONCILE_SCRIPT_VERSION, " file=", fn, " stage_exit=", g_diag_exit_code,
            " deals_rows=", g_diag_deals_data_rows_guess, " sessions=", g_diag_summary_sessions_loaded);
}

// -------------------- OnStart --------------------
int OnStart()
{
   // Reset diagnostyki na poczatku przebiegu (MT5_CHECK zbiera stan z calego OnStart).
   g_diag_exit_code = 0;
   g_diag_exit_detail = "";
   g_diag_summary_target_iso = "";
   g_diag_prev_iso_date = "";
   g_diag_prev_day_ok = false;
   g_diag_prev_day_end_balance = 0.0;

   ulong cur_login = (ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   if(cur_login != InpLogin)
   {
      Print("StageA: BLAD konto: terminal=", cur_login, " skrypt oczekuje InpLogin=", InpLogin);
      return 99;
   }

   string target_iso_date = IsoDateFromTag(InpDateTag);
   if(target_iso_date == "")
   {
      Print("StageA: bad InpDateTag=", InpDateTag, " expected dd-mm-yyyy");
      g_diag_exit_code = 1;
      g_diag_exit_detail = "BAD_DATE_TAG";
      WriteMt5CheckReportFull();
      return 1;
   }
   g_diag_summary_target_iso = target_iso_date;

   string src_deals = SourceDealsFilename();
   string out_deals = ReconciledDealsFilename();

   string src_summary = SourceSummaryFilename();
   string out_summary = ReconciledSummaryFilename();

   // 1) deals: copy to reconciled (deal data juz masz, Stage A to wylacznie "inputs")
   if(!EnsureOutputDealsCopy(src_deals, out_deals))
   {
      g_diag_exit_code = 2;
      g_diag_exit_detail = g_diag_deals_fail_reason;
      if(g_diag_exit_detail == "")
         g_diag_exit_detail = "DEALS_COPY_FAILED";
      WriteMt5CheckReportFull();
      return 2;
   }

   // 2) summary: poprawiamy start_balance/end_balance wedlug ciaglosci sesji
   SessOut sessions[];
   ulong first_sid = 0;
   ulong min_sid = 0;
   double fallback_source_start_balance_for_min_sid = 0.0;

   if(!LoadSourceSessionsForDate(src_summary, target_iso_date, sessions, first_sid, min_sid, fallback_source_start_balance_for_min_sid))
   {
      g_diag_exit_code = 3;
      g_diag_exit_detail = g_diag_summary_fail_reason;
      if(g_diag_exit_detail == "")
         g_diag_exit_detail = "LOAD_SESSIONS_FAILED";
      WriteMt5CheckReportFull();
      return 3;
   }

   SortSessionsBySid(sessions);

   // Prev day baseline (start_balance dla pierwszej sesji na date_tag)
   datetime target_midnight = DatetimeFromIsoDateAtMidnight(target_iso_date);
   if(target_midnight == 0)
   {
      Print("StageA: cannot parse target_midnight for=", target_iso_date);
      g_diag_exit_code = 4;
      g_diag_exit_detail = "BAD_TARGET_MIDNIGHT";
      WriteMt5CheckReportFull();
      return 4;
   }

   string prev_iso_date = DateStr(target_midnight - 86400);
   g_diag_prev_iso_date = prev_iso_date;

   double prev_day_last_end_balance = 0.0;
   bool ok_prev = LoadPrevDayLastEndBalance(src_summary, prev_iso_date, prev_day_last_end_balance);
   g_diag_prev_day_ok = ok_prev;
   g_diag_prev_day_end_balance = prev_day_last_end_balance;

   double start_balance_first = 0.0;
   if(sessions[0].session_id == 0)
   {
      // start of day baseline comes from prev-day last end_balance
      start_balance_first = (ok_prev ? prev_day_last_end_balance : fallback_source_start_balance_for_min_sid);
   }
   else
   {
      // If first session_id isn't 0, fallback to its source start_balance (minimal safe option)
      start_balance_first = fallback_source_start_balance_for_min_sid;
   }

   // Opcja: nie nadpisuj już wygenerowanego pliku reconciled summary (bezpiecznik przed przypadkowym kasowaniem).
   if(InpAbortIfReconciledSummaryExists)
   {
      int hx = FileOpen(out_summary, FILE_READ | FILE_COMMON | FILE_TXT);
      if(hx != INVALID_HANDLE)
      {
         long zz = FileSize(hx);
         FileClose(hx);
         if(zz > 80)
         {
            Print("StageA: ABORT — reconciled summary już istnieje (bytes=", (string)zz, "). ",
                  "Ustaw InpAbortIfReconciledSummaryExists=false aby nadpisać. file=", out_summary);
            g_diag_exit_code = 6;
            g_diag_exit_detail = "ABORT_EXISTING_RECONCILED_SUMMARY";
            WriteMt5CheckReportFull();
            return 6;
         }
      }
   }

   if(!WriteReconciledSummary(out_summary, target_iso_date, sessions, start_balance_first))
   {
      g_diag_exit_code = 5;
      g_diag_exit_detail = "WRITE_RECONCILED_SUMMARY_FAILED";
      WriteMt5CheckReportFull();
      return 5;
   }

   Print("StageA: DONE. target=", target_iso_date,
         " out_summary=", out_summary,
         " out_deals=", out_deals);
   g_diag_exit_code = 0;
   g_diag_exit_detail = "OK";
   WriteMt5CheckReportFull();
   return 0;
}

