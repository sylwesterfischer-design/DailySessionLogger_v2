#property strict
#property script_show_inputs

// Flush: bierze plik DailySessionDeals<login>_RECONCILED.csv i używa go do naprawy
// w DailySessionDeals<login>.csv (deduplikacja po deal_ticket).
//
// Domyślnie działa w trybie TEST (nie modyfikuje źródła).

input ulong  InpLogin = 11720331;
input bool   InpApplyToReal = false;
input string InpSourceDealsFile = ""; // jeśli puste => auto: DailySessionDeals<login>.csv
input string InpReconciledDealsFile = ""; // jeśli puste => auto: DailySessionDeals<login>_RECONCILED.csv

string EnsureHeader = 
   "date;konto;session_id;"
   "deal_time;deal_ticket;symbol;direction;volume;price;"
   "profit_only;"
   "max_session_equity_drawdown;max_session_profit;"
   "max_total_lot;"
   "max_margin_burned;max_session_equity_burned_percent;account_reset;"
   "minute_session_start;minute_session_end";

string TrimSpaces(string s)
{
   int i0 = 0;
   int i1 = StringLen(s) - 1;
   while(i0 <= i1 && (s[i0] == ' ' || s[i0] == '\t' || s[i0] == '\r' || s[i0] == '\n')) i0++;
   while(i1 >= i0 && (s[i1] == ' ' || s[i1] == '\t' || s[i1] == '\r' || s[i1] == '\n')) i1--;
   if(i1 < i0) return "";
   return StringSubstr(s, i0, i1 - i0 + 1);
}

ulong ParseULongSimple(const string token)
{
   string s = TrimSpaces(token);
   if(StringLen(s) > 0 && (uchar)s[0] == 39) // apostrophe
      s = StringSubstr(s, 1);
   if(s == "") return 0;
   return (ulong)StringToInteger(s);
}

struct RecDeal
{
   ulong deal_ticket;
   string line;    // gotowy wiersz
   bool written;
};

int FindDealIndex(RecDeal &recs[], ulong deal_ticket)
{
   for(int i = 0; i < ArraySize(recs); i++)
      if(recs[i].deal_ticket == deal_ticket) return i;
   return -1;
}

string ReconciledFilename()
{
   if(InpReconciledDealsFile != "")
      return InpReconciledDealsFile;
   return StringFormat("DailySessionDeals%I64u_RECONCILED.csv", InpLogin);
}

string SourceFilename()
{
   if(InpSourceDealsFile != "")
      return InpSourceDealsFile;
   return StringFormat("DailySessionDeals%I64u.csv", InpLogin);
}

string DestinationFilename()
{
   if(InpApplyToReal)
      return SourceFilename();
   return StringFormat("DailySessionDeals%I64u_FLUSH_TEST.csv", InpLogin);
}

bool LoadReconciledDeals(const string reconciled_file, RecDeal &out[])
{
   ArrayResize(out, 0);
   int h = FileOpen(reconciled_file, FILE_READ | FILE_COMMON | FILE_TXT);
   if(h == INVALID_HANDLE)
   {
      Print("FlushDeals: cannot open reconciled file=", reconciled_file, " err=", GetLastError());
      return false;
   }

   long sz = FileSize(h);
   string content = (sz > 0 ? FileReadString(h, (int)sz) : "");
   FileClose(h);
   if(content == "")
      return false;

   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");

   string lines[];
   int n = StringSplit(content, '\n', lines);
   for(int li = 0; li < n; li++)
   {
      string ln = TrimSpaces(lines[li]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0) continue;

      string cols[];
      int cn = StringSplit(ln, ';', cols);
      if(cn < 18) continue;

      ulong deal_ticket = ParseULongSimple(cols[4]); // deal_ticket = kolumna 5 (index 4)
      if(deal_ticket == 0) continue;

      int idx = FindDealIndex(out, deal_ticket);
      if(idx < 0)
      {
         int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k].deal_ticket = deal_ticket;
         out[k].line = ln;
         out[k].written = false;
      }
      else
      {
         // keep last
         out[idx].line = ln;
      }
   }

   Print("FlushDeals: loaded reconciled deals=", ArraySize(out));
   return (ArraySize(out) > 0);
}

bool RebuildDeals(const string source_file, const string dest_file, const string reconciled_file)
{
   RecDeal recs[];
   if(!LoadReconciledDeals(reconciled_file, recs))
   {
      Print("FlushDeals: no reconciled deals -> nothing to do.");
      return false;
   }

   int hs = FileOpen(source_file, FILE_READ | FILE_COMMON | FILE_TXT);
   if(hs == INVALID_HANDLE)
   {
      Print("FlushDeals: cannot open source deals file=", source_file, " err=", GetLastError());
      return false;
   }

   long sz = FileSize(hs);
   string content = (sz > 0 ? FileReadString(hs, (int)sz) : "");
   FileClose(hs);
   if(content == "")
   {
      Print("FlushDeals: source deals empty=", source_file);
      return false;
   }

   StringReplace(content, "\r\n", "\n");
   StringReplace(content, "\r", "\n");

   string lines[];
   int n = StringSplit(content, '\n', lines);

   int hd = FileOpen(dest_file, FILE_WRITE | FILE_COMMON | FILE_TXT);
   if(hd == INVALID_HANDLE)
   {
      Print("FlushDeals: cannot open dest for write=", dest_file, " err=", GetLastError());
      return false;
   }

   FileWriteString(hd, "sep=;\r\n");
   FileWriteString(hd, EnsureHeader + "\r\n");

   int out_written = 0;
   for(int li = 0; li < n; li++)
   {
      string ln = TrimSpaces(lines[li]);
      if(ln == "") continue;
      if(StringFind(ln, "sep=;") == 0) continue;
      if(StringFind(ln, "date;konto;session_id") == 0) continue;

      string cols[];
      int cn = StringSplit(ln, ';', cols);
      if(cn < 18) continue;

      ulong deal_ticket = ParseULongSimple(cols[4]);
      if(deal_ticket == 0) { FileWriteString(hd, ln + "\r\n"); out_written++; continue; }

      int idx = FindDealIndex(recs, deal_ticket);
      if(idx >= 0)
      {
         if(!recs[idx].written)
         {
            FileWriteString(hd, recs[idx].line + "\r\n");
            recs[idx].written = true;
            out_written++;
         }
         continue; // skip old line (or duplicate)
      }

      FileWriteString(hd, ln + "\r\n");
      out_written++;
   }

   // Append missing reconciled deals.
   for(int i = 0; i < ArraySize(recs); i++)
   {
      if(!recs[i].written)
      {
         FileWriteString(hd, recs[i].line + "\r\n");
         out_written++;
      }
   }

   FileClose(hd);
   Print("FlushDeals: DONE dest=", dest_file, " written_rows=", out_written);
   return true;
}

int OnStart()
{
   string source_file = SourceFilename();
   string reconciled_file = ReconciledFilename();
   string dest_file = DestinationFilename();

   Print("FlushDeals: login=", InpLogin, " reconciled_file=", reconciled_file,
         " source_file=", source_file, " dest_file=", dest_file,
         " applyToReal=", (InpApplyToReal ? "true" : "false"));

   bool ok = RebuildDeals(source_file, dest_file, reconciled_file);
   return ok ? INIT_SUCCEEDED : INIT_FAILED;
}

