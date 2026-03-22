#property strict
#property script_show_inputs

// Stage A (RECONCILED inputs):
// - nie modyfikuje produkcyjnych CSV
// - tworzy pliki:
//   * DailySessionDeals11720331_RECONCILED.csv
//   * DailySessionSummary_RECONCILED_11720331_<dd-mm-yyyy>.csv
//
// Uwaga: w tej wersji start_balance/end_balance dla sesji liczymy z poprawionej "ciągłości"
// na podstawie:
// - source DailySessionSummary.csv (max_session_profit)
// - poprawnej bazy: last end_balance z poprzedniego dnia (prev day last session)
//
// Ten plik ma po prostu odblokowac pipeline A->B->C, gdy pełna wersja Stage-A
// była pusta/utracona.
//
// Wersja pliku (kompilacja MT5): 2026-03-20 — poprawki: StringToDouble zamiast StrToDouble,
// StringReplace bez przypisania do stringa, parametr SessOut &sessions[], ulong FileSize.

input ulong  InpLogin   = 11720331;
input string InpDateTag = "18-03-2026"; // dd-mm-yyyy (zgodne z Flush script)
input bool   InpDryRun   = false;      // true => nie pisz plikow

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
   string content = "";
   if(!ReadFileCommonToString(source_deals, content))
   {
      Print("StageA: cannot read source deals=", source_deals, " err=", GetLastError());
      return false;
   }
   if(content == "")
   {
      Print("StageA: source deals empty=", source_deals);
      return false;
   }

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

   string content = "";
   if(!ReadFileCommonToString(source_summary, content))
   {
      Print("StageA: cannot read source summary=", source_summary, " err=", GetLastError());
      return false;
   }
   if(content == "")
   {
      Print("StageA: source summary empty=", source_summary);
      return false;
   }

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
      if(date_str != target_iso_date) continue;
      if(konto != InpLogin) continue;

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
      Print("StageA: no sessions found in source summary for date=", target_iso_date, " konto=", InpLogin);
      return false;
   }
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

// -------------------- OnStart --------------------
int OnStart()
{
   string target_iso_date = IsoDateFromTag(InpDateTag);
   if(target_iso_date == "")
   {
      Print("StageA: bad InpDateTag=", InpDateTag, " expected dd-mm-yyyy");
      return 1;
   }

   string src_deals = SourceDealsFilename();
   string out_deals = ReconciledDealsFilename();

   string src_summary = SourceSummaryFilename();
   string out_summary = ReconciledSummaryFilename();

   // 1) deals: copy to reconciled (deal data juz masz, Stage A to wylacznie "inputs")
   if(!EnsureOutputDealsCopy(src_deals, out_deals))
      return 2;

   // 2) summary: poprawiamy start_balance/end_balance wedlug ciaglosci sesji
   SessOut sessions[];
   ulong first_sid = 0;
   ulong min_sid = 0;
   double fallback_source_start_balance_for_min_sid = 0.0;

   if(!LoadSourceSessionsForDate(src_summary, target_iso_date, sessions, first_sid, min_sid, fallback_source_start_balance_for_min_sid))
      return 3;

   SortSessionsBySid(sessions);

   // Prev day baseline (start_balance dla pierwszej sesji na date_tag)
   datetime target_midnight = DatetimeFromIsoDateAtMidnight(target_iso_date);
   if(target_midnight == 0)
   {
      Print("StageA: cannot parse target_midnight for=", target_iso_date);
      return 4;
   }

   string prev_iso_date = DateStr(target_midnight - 86400);

   double prev_day_last_end_balance = 0.0;
   bool ok_prev = LoadPrevDayLastEndBalance(src_summary, prev_iso_date, prev_day_last_end_balance);

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

   if(!WriteReconciledSummary(out_summary, target_iso_date, sessions, start_balance_first))
      return 5;

   Print("StageA: DONE. target=", target_iso_date,
         " out_summary=", out_summary,
         " out_deals=", out_deals);
   return 0;
}

