//+------------------------------------------------------------------+
//| ExportDailyHistoryHtml.mq5                                       |
//| Codziennie o ustawionej godzinie (domyślnie 23:59) zapisuje      |
//| plik HTML z historii **dealów** (HistoryDeal), nie z menu        |
//| „Raport → HTML” MT5 (brak API na identyczny szablon terminala). |
//| HTML nadaje się do przeglądarki; opcjonalnie do insertu Python   |
//| (--layout deals-default). Żadnego CSV ten EA nie tworzy.        |
//| Deduplikacja (ticket vs CSV) = wyłącznie insert_from_mt5_html.py |
//| po ręcznym uruchomieniu — ten EA jej nie wykonuje.               |
//|                                                                  |
//| MT5 **nie pozwala** EA zapisywać poza sandboxem (Files/Common).  |
//| Folder docelowy = junction: Common\Files\<InpSubfolder> → repo.  |
//| Mapowanie: docs/EXPORT_DAILY_HTML_JUNCTIONS.md                    |
//+------------------------------------------------------------------+
#property copyright "DailySessionLogger_v2 helper"
#property version   "1.01"
#property strict

// Nazwa obiektu przycisku na wykresie (unikalna per ChartID)
#define EDH_BTN_PREFIX "EDH_ExportHtmlNow_"

// --- harmonogram (czas **serwera** brokera) ---
input int    InpExportHour       = 23;     // godzina uruchomienia eksportu
input int    InpExportMinute     = 59;     // minuta
input int    InpExportSecondMax  = 59;     // eksport przy pierwszym timerze z sekundą <= tej wartości (okno w minucie)

// --- gdzie zapisać (względem Common\Files, patrz FILE_COMMON) ---
input string InpSubfolder        = "reports_10827887"; // junction → ...\DailySessionLogger_v2\reports_<LOGIN>
input string InpFileNamePrefix   = "ReportHistoryAuto"; // plik: <prefix>-<login>_YYYY-MM-DD.html

// --- test / serwis ---
input bool   InpRunOnceNow       = false;  // true = jednorazowy eksport przy starcie (bez czekania na 23:59)
input bool   InpShowExportButton = true;   // przycisk na wykresie „Eksport HTML teraz” (pokazowy / bez czekania do 23:59)
input int    InpTimerSeconds     = 1;      // jak często sprawdzać zegar (1 s = precyzyjne 23:59)

// Flaga: żeby nie wyeksportować dwa razy tego samego dnia kalendarzowego serwera
int g_exported_ymd = 0;

//+------------------------------------------------------------------+
//| Pełna nazwa przycisku (unikalna dla tego wykresu)                 |
//+------------------------------------------------------------------+
string EdhButtonName()
{
   return EDH_BTN_PREFIX + IntegerToString(ChartID());
}

//+------------------------------------------------------------------+
//| Rysuj przycisk ręcznego eksportu (lewy górny róg wykresu)        |
//+------------------------------------------------------------------+
void CreateExportButtonOnChart()
{
   if(!InpShowExportButton)
      return;
   string nm = EdhButtonName();
   if(ObjectFind(0, nm) >= 0)
      return;
   // Tworzymy przycisk — klik wywołuje eksport tego samego dnia co harmonogram
   if(!ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0))
   {
      Print("ExportDailyHistoryHtml: ObjectCreate button failed, err=", GetLastError());
      return;
   }
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 22);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, 168);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, 26);
   ObjectSetString(0, nm, OBJPROP_TEXT, "Eksport HTML teraz");
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, clrDimGray);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Usuń przycisk przy zdejmowaniu EA                                |
//+------------------------------------------------------------------+
void DeleteExportButtonFromChart()
{
   ObjectDelete(0, EdhButtonName());
}

//+------------------------------------------------------------------+
//| Pomoc: początek dnia kalendarzowego (czas serwera)               |
//+------------------------------------------------------------------+
datetime DayStartServer(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| YYYYMMDD dla czasu serwera                                       |
//+------------------------------------------------------------------+
int YmdServer(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

//+------------------------------------------------------------------+
//| buy / sell z DEAL_TYPE                                           |
//+------------------------------------------------------------------+
string DealTypeToStr(const long typ)
{
   if(typ == DEAL_TYPE_BUY)  return "buy";
   if(typ == DEAL_TYPE_SELL) return "sell";
   return "unknown";
}

//+------------------------------------------------------------------+
//| Budowa jednego wiersza <tr>…</tr> — kolejność kolumn jak         |
//| deals-default w insert_from_mt5_html.py (min. 11 komórek):       |
//| 0 czas, 1 ticket, 2 symbol, 3 typ, 4 puste, 5 vol, 6 price,      |
//| 7 prowizja, 8 swap, 9 profit, 10 saldo (placeholder)             |
//+------------------------------------------------------------------+
string HtmlEscapeMinimal(const string s)
{
   string r = s;
   StringReplace(r, "&", "&amp;");
   StringReplace(r, "<", "&lt;");
   StringReplace(r, ">", "&gt;");
   return r;
}

string BuildDealRow(const ulong deal_ticket)
{
   datetime t = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
   string sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   long   dtyp = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
   double vol  = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   double prc  = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
   double comm = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
   double prof = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);

   string ts = TimeToString(t, TIME_DATE | TIME_SECONDS);
   StringReplace(ts, ".", "."); // MT5 już daje YYYY.MM.DD — zostawiamy jak w eksporcie MT5

   string vols = DoubleToString(vol, 2);
   int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(dig < 0)
      dig = _Digits;
   string prcs = DoubleToString(prc, dig);
   string coms = DoubleToString(comm, 2);
   string sws  = DoubleToString(swap, 2);
   string pfs  = DoubleToString(prof, 2);

   string row = "<tr>";
   row += "<td nowrap>" + HtmlEscapeMinimal(ts) + "</td>";
   row += "<td nowrap>" + IntegerToString((long)deal_ticket) + "</td>";
   row += "<td nowrap>" + HtmlEscapeMinimal(sym) + "</td>";
   row += "<td nowrap>" + DealTypeToStr(dtyp) + "</td>";
   row += "<td></td>"; // kolumna 4 — placeholder (jak w typowym układzie Deals)
   row += "<td nowrap>" + vols + "</td>";
   row += "<td nowrap>" + prcs + "</td>";
   row += "<td nowrap>" + coms + "</td>";
   row += "<td nowrap>" + sws + "</td>";
   row += "<td nowrap>" + pfs + "</td>";
   row += "<td nowrap>0</td>"; // brak ciągłego salda z historii — insert i tak czyta pole
   row += "</tr>\r\n";
   return row;
}

//+------------------------------------------------------------------+
//| Eksport całego dnia (od północy serwera do „teraz”)              |
//+------------------------------------------------------------------+
bool ExportDayHtml()
{
   datetime now = TimeTradeServer();
   datetime day_start = DayStartServer(now);
   datetime day_end   = now; // przy odpaleniu o 23:59 obejmuje prawie cały dzień

   if(!HistorySelect(day_start, day_end))
   {
      Print("ExportDailyHistoryHtml: HistorySelect failed, err=", GetLastError());
      return false;
   }

   int total = HistoryDealsTotal();
   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      // Tylko buy/sell (pomijamy m.in. balance / credit deal types w HTML pod insert)
      long typ = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
         continue;
      int sz = ArraySize(tickets);
      ArrayResize(tickets, sz + 1);
      tickets[sz] = ticket;
   }
   int n = ArraySize(tickets);

   // Sort prosty: po czasie, potem ticket (bąbelkowo — n rzadko ogromne przy eksporcie dziennym)
   for(int a = 0; a < n - 1; a++)
      for(int b = a + 1; b < n; b++)
      {
         datetime ta = (datetime)HistoryDealGetInteger(tickets[a], DEAL_TIME);
         datetime tb = (datetime)HistoryDealGetInteger(tickets[b], DEAL_TIME);
         if(ta > tb || (ta == tb && tickets[a] > tickets[b]))
         {
            ulong tmp = tickets[a];
            tickets[a] = tickets[b];
            tickets[b] = tmp;
         }
      }

   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string rel_dir = InpSubfolder;
   // Utwórz podfolder w Common\Files (jeśli już istnieje — OK; junction może być utworzony ręcznie)
   if(StringLen(rel_dir) > 0)
      FolderCreate(rel_dir, FILE_COMMON);

   MqlDateTime dtx;
   TimeToStruct(day_start, dtx);
   string date_tag = StringFormat("%04d-%02d-%02d", dtx.year, dtx.mon, dtx.day);
   string fname = InpFileNamePrefix + "-" + IntegerToString(login) + "_" + date_tag + ".html";
   if(StringLen(rel_dir) > 0)
      fname = rel_dir + "\\" + fname;

   int handle = FileOpen(fname,
                          FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_UNICODE);
   if(handle == INVALID_HANDLE)
   {
      Print("ExportDailyHistoryHtml: FileOpen failed, err=", GetLastError(), " file=", fname);
      return false;
   }

   // Zapis w kawałkach — jeden długi string mógłby przekroczyć limit MQL5 przy tysiącach deali
   bool ok = true;
   ok = ok && (FileWriteString(handle,
               "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\r\n") > 0);
   ok = ok && (FileWriteString(handle,
               "<html><head><meta charset=\"utf-16\"/><title>Auto export deals</title></head><body>\r\n") > 0);
   ok = ok && (FileWriteString(handle,
               "<div align=\"center\"><table cellspacing=\"1\" cellpadding=\"3\" border=\"0\">\r\n") > 0);
   ok = ok && (FileWriteString(handle,
               "<tr align=\"center\"><th>Time</th><th>Deal</th><th>Symbol</th><th>Type</th><th></th>") > 0);
   ok = ok && (FileWriteString(handle,
               "<th>Volume</th><th>Price</th><th>Commission</th><th>Swap</th><th>Profit</th><th>Balance</th></tr>\r\n") > 0);

   for(int i = 0; i < n && ok; i++)
      ok = ok && (FileWriteString(handle, BuildDealRow(tickets[i])) > 0);

   ok = ok && (FileWriteString(handle, "</table></div></body></html>") > 0);

   if(!ok)
   {
      Print("ExportDailyHistoryHtml: FileWriteString failed, err=", GetLastError());
      FileClose(handle);
      return false;
   }
   FileClose(handle);
   Print("ExportDailyHistoryHtml: OK nDeals=", n, " file=", fname, " COMMON\\Files");
   return true;
}

//+------------------------------------------------------------------+
//| Sprawdź, czy należy uruchomić eksport                            |
//+------------------------------------------------------------------+
void TryScheduledExport()
{
   datetime ts = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(ts, dt);

   int ymd = YmdServer(ts);

   if(dt.hour != InpExportHour || dt.min != InpExportMinute)
      return;
   if(dt.sec > InpExportSecondMax)
      return;
   if(g_exported_ymd == ymd)
      return;

   if(ExportDayHtml())
      g_exported_ymd = ymd;
}

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(MathMax(1, InpTimerSeconds));
   Print("ExportDailyHistoryHtml: start, server=", TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS),
         " subfolder=", InpSubfolder, " schedule=", IntegerToString(InpExportHour), ":", IntegerToString(InpExportMinute));
   CreateExportButtonOnChart();
   // Test bez czekania na 23:59: ustaw InpRunOnceNow=true, uruchom EA, potem wyłącz (kompilacja / input)
   if(InpRunOnceNow)
   {
      int ymd = YmdServer(TimeTradeServer());
      if(ExportDayHtml())
         g_exported_ymd = ymd;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteExportButtonFromChart();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   TryScheduledExport();
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Pusty — EA musi być na wykresie; timer wystarczy
}

//+------------------------------------------------------------------+
//| Klik w przycisk = natychmiastowy eksport (nadpisze plik z dzisiejszą datą) |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam != EdhButtonName())
      return;
   // Ręczny eksport: nie ustawiamy g_exported_ymd — harmonogram o 23:59 nadal może zapisać ponownie
   bool ok = ExportDayHtml();
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw(0);
   if(ok)
      Alert("ExportDailyHistoryHtml: zapisano HTML (ręcznie). Sprawdź Experts + folder Common\\Files.");
   else
      Alert("ExportDailyHistoryHtml: błąd zapisu — zobacz zakładkę Experts.");
}

//+------------------------------------------------------------------+
