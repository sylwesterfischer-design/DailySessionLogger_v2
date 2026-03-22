#property strict
#property script_show_inputs

// Flush: bierze plik *_RECONCILED_<login>_<dateTag>.csv i używa go do naprawy wierszy
// w DailySessionSummary.csv dla wskazanego `dateTag` (dd-mm-yyyy).
// Domyślnie działa w trybie TEST (nie modyfikuje źródła).

input ulong  InpLogin = 11720331;
input string InpDateTag = "18-03-2026"; // dd-mm-yyyy
input bool   InpApplyToReal = false;    // false => zapis do pliku testowego
input string InpSourceFile = "DailySessionSummary.csv";

string EXPECTED_HEADER =
   "date;konto;session_id;start_balance;end_balance;"
   "max_session_equity_drawdown;max_session_profit;"
   "max_single_lot;max_total_lot;"
   "max_margin_burned;max_session_equity_burned_percent;account_reset;"
   "minute_session_start;minute_session_end";

// `DailySessionSummary_RECONCILED_<login>_<dd-mm-yyyy>.csv`
string ReconciledFilename()
{
   return StringFormat("DailySessionSummary_RECONCILED_%I64u_%s.csv", InpLogin, InpDateTag);
}

string DestinationFilename()
{
   if(InpApplyToReal)
      return InpSourceFile;
   return StringFormat("DailySessionSummary_FLUSH_TEST_%I64u_%s.csv", InpLogin, InpDateTag);
}

string TrimSpaces(string s)
{
   int i0 = 0;
   int i1 = StringLen(s) - 1;
   while(i0 <= i1 && (s[i0] == ' ' || s[i0] == '\t' || s[i0] == '\r' || s[i0] == '\n')) i0++;
   while(i1 >= i0 && (s[i1] == ' ' || s[i1] == '\t' || s[i1] == '\r' || s[i1] == '\n')) i1--;
   if(i1 < i0) return "";
   return StringSubstr(s, i0, i1 - i0 + 1);
}

// Konwersja dd-mm-yyyy => yyyy-mm-dd
string IsoDateFromTag(const string tag)
{
   string parts[];
   int n = StringSplit(tag, '-', parts);
   if(n != 3) return "";
   int day = (int)StringToInteger(parts[0]);
   int mon = (int)StringToInteger(parts[1]);
   int year= (int)StringToInteger(parts[2]);
   return StringFormat("%04d-%02d-%02d", year, mon, day);
}

ulong ParseULongSimple(const string token)
{
   string s = TrimSpaces(token);
   if(StringLen(s) > 0 && (uchar)s[0] == 39) // apostrophe
      s = StringSubstr(s, 1);
   if(s == "") return 0;
   return (ulong)StringToInteger(s);
}

struct RecRow
{
   string date_str; // yyyy-mm-dd
   ulong  konto;
   int    session_id;
   string line;     // gotowy wiersz (bez CRLF)
   bool   written;
};

int FindRecIndex(RecRow &recs[], const string date_str, ulong konto, int session_id)
{
   for(int i = 0; i < ArraySize(recs); i++)
   {
      if(recs[i].date_str == date_str &&
         recs[i].konto == konto &&
         recs[i].session_id == session_id)
         return i;
   }
   return -1;
}

bool LoadReconciledRows(const string reconciled_file, const string target_date_str, RecRow &out[])
{
   ArrayResize(out, 0);
   int h = FileOpen(reconciled_file, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("FlushSummary: cannot open reconciled file=", reconciled_file, " err=", GetLastError());
      return false;
   }

   long sz = FileSize(h);
   string content = (sz > 0 ? FileReadString(h, (int)sz) : "");
   FileClose(h);
   if(content == "")
   {
      Print("FlushSummary: reconciled file empty=", reconciled_file);
      return false;
   }

   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");

   string lines[];
   int n = StringSplit(content, '\n', lines);
   int added = 0;
   for(int li = 0; li < n; li++)
   {
      string ln = TrimSpaces(lines[li]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0) continue;

      string cols[];
      int cn = StringSplit(ln, ';', cols);
      if(cn < 14) continue;

      string d = TrimSpaces(cols[0]);
      ulong konto = ParseULongSimple(cols[1]);
      int sid = (int)ParseULongSimple(cols[2]);

      if(d != target_date_str) continue;
      if(konto != InpLogin) continue;

      int idx = FindRecIndex(out, d, konto, sid);
      if(idx < 0)
      {
         int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k].date_str = d;
         out[k].konto = konto;
         out[k].session_id = sid;
         out[k].line = ln;
         out[k].written = false;
         added++;
      }
      else
      {
         // keep last occurrence
         out[idx].line = ln;
      }
   }

   Print("FlushSummary: loaded reconciled rows for date=", target_date_str, " count=", ArraySize(out));
   return (ArraySize(out) > 0);
}

bool RebuildSummary(const string source_file, const string dest_file, const string reconciled_file, const string target_date_str)
{
   RecRow recs[];
   if(!LoadReconciledRows(reconciled_file, target_date_str, recs))
   {
      Print("FlushSummary: no reconciled rows -> nothing to do.");
      return false;
   }

   int hs = FileOpen(source_file, FILE_READ | FILE_COMMON | FILE_TXT);
   if(hs == INVALID_HANDLE)
   {
      Print("FlushSummary: cannot open source file=", source_file, " err=", GetLastError());
      return false;
   }

   long sz = FileSize(hs);
   string content = (sz > 0 ? FileReadString(hs, (int)sz) : "");
   FileClose(hs);
   if(content == "")
   {
      Print("FlushSummary: source file empty=", source_file);
      return false;
   }

   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");

   string lines[];
   int n = StringSplit(content, '\n', lines);

   int hd = FileOpen(dest_file, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(hd == INVALID_HANDLE)
   {
      Print("FlushSummary: cannot open dest for write=", dest_file, " err=", GetLastError());
      return false;
   }

   FileWriteString(hd, "sep=;\r\n");
   FileWriteString(hd, EXPECTED_HEADER + "\r\n");

   int out_written = 0;
   for(int li = 0; li < n; li++)
   {
      string ln = TrimSpaces(lines[li]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0) continue;

      string cols[];
      int cn = StringSplit(ln, ';', cols);
      if(cn < 14)
         continue;

      string d = TrimSpaces(cols[0]);
      ulong konto = ParseULongSimple(cols[1]);
      int sid = (int)ParseULongSimple(cols[2]);

      if(d == target_date_str && konto == InpLogin)
      {
         int idx = FindRecIndex(recs, d, konto, sid);
         if(idx >= 0)
         {
            if(!recs[idx].written)
            {
               FileWriteString(hd, recs[idx].line + "\r\n");
               recs[idx].written = true;
               out_written++;
            }
            continue; // replace done (or skip duplicate)
         }
      }

      FileWriteString(hd, ln + "\r\n");
   }

   // Append missing reconciled rows.
   for(int i = 0; i < ArraySize(recs); i++)
   {
      if(!recs[i].written)
      {
         FileWriteString(hd, recs[i].line + "\r\n");
         out_written++;
      }
   }

   FileClose(hd);
   Print("FlushSummary: DONE dest=", dest_file, " replaced_rows=", out_written);
   return true;
}

int OnStart()
{
   string target_date_str = IsoDateFromTag(InpDateTag);
   if(target_date_str == "")
   {
      Print("FlushSummary: wrong InpDateTag=", InpDateTag, " expected dd-mm-yyyy");
      return(INIT_FAILED);
   }

   string recon_file = ReconciledFilename();
   string dest_file = DestinationFilename();

   Print("FlushSummary: login=", InpLogin, " dateTag=", InpDateTag,
         " target_date_str=", target_date_str,
         " recon_file=", recon_file,
         " dest_file=", dest_file,
         " applyToReal=", (InpApplyToReal ? "true" : "false"));

   bool ok = RebuildSummary(InpSourceFile, dest_file, recon_file, target_date_str);
   return(ok ? INIT_SUCCEEDED : INIT_FAILED);
}

