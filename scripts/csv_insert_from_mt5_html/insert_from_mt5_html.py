#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
INSERT brakujących deali / wierszy summary do KOPII CSV na podstawie raportu HTML z MT5.

Mapowanie kolumn Raport Historii PL (Pozycje) → CSV: docs/MTP_INSERT_HTML_POSITIONS_PL_MAPPING.md

Ta zmiana NIE zmienia definicji plików:
  • DailySessionDeals<konto>.csv — 18 kolumn (jak EnsureHeaderDailyDealsPerAccount w EA)
  • DailySessionSummary.csv — 14 kolumn (jak EnsureHeaderDailyGlobal w EA)

Wyjście domyślnie: pliki *_INSERT.csv (pełna kopia wejściowych wierszy + dopisane brakujące),
żeby najpierw zweryfikować diff w Excelu / Notepad++ zanim podmienisz oryginał.

Ograniczenia (HTML ≠ pełna historia MT5 API):
  • Brak prawdziwej sesji EA (0→pozycje→flat w jednej minucie). Domyślnie: jedna
    syntetyczna sesja na dzień kalendarzowy dla NOWYCH deali (--session-mode day),
    albo jedna sesja na cały insert (--session-mode batch).
  • Kolumny sesyjne (DD equity, margin %, itp.) — uzupełniane zerami / pusto tam,
    gdzie HTML nie dostarcza danych (zgodnie z formatem liczb jak w EA: przecinek).

Użycie (PowerShell, z korzenia repo):
  py scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py ^
    --html "C:\\path\\ReportStatement.htm" ^
    --konto 11693814 ^
    --deals-in  "C:\\...\\DailySessionDeals11693814.csv" ^
    --summary-in "C:\\...\\DailySessionSummary.csv" ^
    --dry-run

  # Zapis plików *_INSERT.csv obok wejściowych (lub --deals-out / --summary-out):
  py scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py --html Report.htm --konto 11693814 ...
"""
from __future__ import annotations

import argparse
import csv
import html as html_module
import io
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

# --- Schematy (musi być zgodne z DailySessionLogger_v2.mq5) ---
DEALS_HEADER_18 = (
    "date;konto;session_id;deal_time;deal_ticket;symbol;direction;volume;price;"
    "profit_only;max_session_equity_drawdown;max_session_profit;max_total_lot;"
    "max_margin_burned;max_session_equity_burned_percent;account_reset;"
    "minute_session_start;minute_session_end"
)

SUMMARY_HEADER_14 = (
    "date;konto;session_id;start_balance;end_balance;max_session_equity_drawdown;"
    "max_session_profit;max_single_lot;max_total_lot;max_margin_burned;"
    "max_session_equity_burned_percent;account_reset;minute_session_start;"
    "minute_session_end"
)

EXPECTED_DEALS_COLS = 18
EXPECTED_SUMMARY_COLS = 14


def strip_bom(s: str) -> str:
    return s[1:] if s.startswith("\ufeff") else s


def read_path_mt5_text(path: Path) -> str:
    """
    Odczyt pliku tekstowego z MT5 (HTML / CSV): często UTF-16 LE z BOM.
    Gdy wczytamy jako UTF-8, nagłówek CSV „psuje się” (pozorne 2 kolumny),
    a regex na HTML nie widzi tagów — stąd puste wyniki insertu.
    """
    raw = path.read_bytes()
    # BOM UTF-16 LE / BE — decode("utf-16") sam konsumuje BOM i wybiera endianness
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return strip_bom(raw.decode("utf-16"))
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig")
    return raw.decode("utf-8", errors="replace")


def pl_num(x: float, digits: int = 2) -> str:
    """Format jak DoubleToString + przecinek (uproszczenie względem EA)."""
    s = f"{x:.{digits}f}"
    return s.replace(".", ",")


def pl_lot(x: float) -> str:
    return pl_num(x, 2)


def parse_mt5_html_datetime(cell: str) -> Optional[datetime]:
    """
    Typowy eksport MT5: 2026.03.20 14:30:45 lub 2026.03.20 14:30
    Zwraca naive datetime (lokalny czas z raportu — bez strefy).
    """
    cell = cell.strip()
    m = re.match(
        r"^(\d{4})\.(\d{2})\.(\d{2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$",
        cell,
    )
    if not m:
        return None
    y, mo, d, h, mi, sec = m.groups()
    return datetime(
        int(y),
        int(mo),
        int(d),
        int(h),
        int(mi),
        int(sec) if sec else 0,
    )


def minute_str_local_ea(dt: datetime) -> str:
    """MinuteStrLocal w MQ5: DD.MM.YYYY HH:MM"""
    return f"{dt.day:02d}.{dt.month:02d}.{dt.year:04d} {dt.hour:02d}:{dt.minute:02d}"


def date_str_ea(dt: datetime) -> str:
    """DateStr w MQ5: YYYY-MM-DD"""
    return f"{dt.year:04d}-{dt.month:02d}-{dt.day:02d}"


def parse_pl_number(s: str) -> float:
    s = strip_bom(s.strip().replace(" ", ""))
    s = s.replace(",", ".")
    s = re.sub(r"[^\d.\-]", "", s)
    if s in ("", "-", ".", "-."):
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def clean_cell(raw: str) -> str:
    t = re.sub(r"<[^>]+>", " ", raw)
    t = html_module.unescape(t)
    return " ".join(t.split())


def iter_table_rows(html: str) -> Iterable[List[str]]:
    """Wyciąga teksty komórek <td>...</td> dla każdego <tr>."""
    for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", html, flags=re.I | re.S):
        cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, flags=re.I | re.S)
        if not cells:
            continue
        yield [clean_cell(c) for c in cells]


@dataclass
class HtmlDeal:
    time: datetime
    ticket: str
    symbol: str
    direction: str  # buy / sell
    volume: float
    price: float
    profit: float
    balance_after: Optional[float]


def row_looks_like_deal(cells: List[str], min_cols: int) -> bool:
    if len(cells) < min_cols:
        return False
    if parse_mt5_html_datetime(cells[0]) is None:
        return False
    if not re.fullmatch(r"\d+", cells[1].strip()):
        return False
    return True


def parse_deals_from_mt5_html(
    html_text: str,
    *,
    col_time: int = 0,
    col_ticket: int = 1,
    col_symbol: int = 2,
    col_type: int = 3,
    col_volume: int = 5,
    col_price: int = 6,
    col_profit: int = -2,
    col_balance: int = -1,
    min_cols: int = 8,
    read_balance: bool = True,
) -> List[HtmlDeal]:
    """
    Heurystyka dla typowego raportu MT5 (sekcja Deals): pierwsza kolumna czas,
    druga ticket. Typ buy/sell zwykle w kolumnie „Type”. Volume/Price/Profit
    — domyślne indeksy jak w angielskim szablonie; jeśli nie pasuje, użyj
    --col-* (wartości ujemne = od końca wiersza, np. -1 = ostatnia kolumna).

    **Layout „positions-pl”** (Raport Historii Trade, PL, sekcja „Pozycje”):
    wiersz ma ukryte komórki colspan; indeksy po wyciągnięciu <td>: 0=czas otwarcia,
    1=ID pozycji (nie ten sam co deal_ticket w EA), 2=symbol, 3=buy/sell, 4=puste (hidden),
    5=wolumen, 6=cena otw., …, 9=czas zamknięcia, 10=cena zamk., 11=prowizja, 12=swap, 13=zysk.
    Dla insertu używamy **czasu zamknięcia** (kolumna 9) jako deal_time.
    """
    deals: List[HtmlDeal] = []
    for cells in iter_table_rows(html_text):
        n = len(cells)
        if n < min_cols:
            continue

        def idx(i: int) -> int:
            return i if i >= 0 else n + i

        if not row_looks_like_deal(cells, min_cols):
            continue

        t = parse_mt5_html_datetime(cells[col_time])
        if t is None:
            continue
        ticket = cells[col_ticket].strip()
        sym = cells[idx(col_symbol)].strip() if col_symbol is not None else ""
        typ = cells[idx(col_type)].strip().lower()
        # Angielski + typowe polskie etykiety eksportu MT5
        if typ in ("kup", "kupno", "buy", "long"):
            typ = "buy"
        elif typ in ("sprzedaz", "sprzedaż", "sell", "short"):
            typ = "sell"
        else:
            continue

        vol = parse_pl_number(cells[idx(col_volume)])
        prc = parse_pl_number(cells[idx(col_price)])
        prof = parse_pl_number(cells[idx(col_profit)])
        # Dla layoutu positions-pl read_balance=False — bal_cell musi być zdefiniowane (bez UnboundLocalError)
        bal: Optional[float] = None
        bal_cell = ""
        if read_balance:
            bal_cell = cells[idx(col_balance)] if abs(col_balance) <= n else ""
            if bal_cell:
                bal = parse_pl_number(bal_cell)

        deals.append(
            HtmlDeal(
                time=t,
                ticket=ticket,
                symbol=sym,
                direction=typ,
                volume=vol,
                price=prc,
                profit=prof,
                balance_after=bal if bal_cell else None,
            )
        )
    # Stabilny porządek: czas, ticket
    deals.sort(key=lambda d: (d.time, int(d.ticket)))
    return deals


def read_sem_csv_rows(path: Path) -> Tuple[Optional[str], List[List[str]]]:
    """Zwraca (pierwsza_linia_sep lub None, wiersze jako listy pól)."""
    raw = read_path_mt5_text(path)
    lines = raw.splitlines()
    if not lines:
        return None, []
    i0 = 0
    sep_line: Optional[str] = None
    if lines[0].strip().lower().startswith("sep="):
        sep_line = lines[0]
        i0 = 1
    rows: List[List[str]] = []
    for line in lines[i0:]:
        if not line.strip():
            continue
        row = next(csv.reader([line], delimiter=";", quotechar='"'))
        rows.append(row)
    return sep_line, rows


def write_sem_csv(path: Path, sep_line: Optional[str], rows: Sequence[Sequence[str]]) -> None:
    buf = io.StringIO()
    if sep_line:
        buf.write(sep_line.rstrip("\r\n") + "\r\n")
    for row in rows:
        sio = io.StringIO()
        w = csv.writer(sio, delimiter=";", quoting=csv.QUOTE_MINIMAL, lineterminator="")
        w.writerow(list(row))
        buf.write(sio.getvalue().rstrip("\r\n") + "\r\n")
    path.write_text(buf.getvalue(), encoding="utf-8", newline="")


def validate_header(row: List[str], expected_cols: int, name: str) -> None:
    if not row:
        raise SystemExit(f"{name}: brak nagłówka")
    if len(row) != expected_cols:
        raise SystemExit(
            f"{name}: oczekiwano {expected_cols} kolumn w nagłówku, jest {len(row)}"
        )


def existing_deal_tickets(deals_rows: List[List[str]]) -> Set[str]:
    s: Set[str] = set()
    for r in deals_rows[1:]:
        if len(r) > 4:
            s.add(r[4].strip())
    return s


def max_session_id_for_konto(rows: List[List[str]], konto: str) -> int:
    m = 0
    for r in rows[1:]:
        if len(r) < 3:
            continue
        if r[1].strip() != str(konto):
            continue
        try:
            m = max(m, int(float(r[2])))
        except ValueError:
            continue
    return m


def summary_keys(rows: List[List[str]]) -> Set[Tuple[str, str, str]]:
    keys: Set[Tuple[str, str, str]] = set()
    for r in rows[1:]:
        if len(r) < 3:
            continue
        keys.add((r[0].strip(), r[1].strip(), r[2].strip()))
    return keys


def build_synthetic_sessions(
    new_deals: List[HtmlDeal],
    session_mode: str,
    base_session_id: int,
) -> Dict[str, Tuple[int, List[HtmlDeal]]]:
    """
    Klucz grupy: dla 'day' -> YYYY-MM-DD, dla 'batch' -> '_all'.
    Wartość: (session_id, lista deali).
    """
    groups: Dict[str, List[HtmlDeal]] = defaultdict(list)
    if session_mode == "batch":
        groups["_all"] = list(new_deals)
    else:
        for d in new_deals:
            k = date_str_ea(d.time)
            groups[k].append(d)
    out: Dict[str, Tuple[int, List[HtmlDeal]]] = {}
    sid = base_session_id
    for key in sorted(groups.keys()):
        sid += 1
        out[key] = (sid, sorted(groups[key], key=lambda x: (x.time, int(x.ticket))))
    return out


def make_deal_csv_row(
    d: HtmlDeal,
    konto: str,
    session_id: int,
    session_profit_total: float,
    session_max_lot: float,
    minute_start: str,
    minute_end: str,
    day_date: str,
) -> List[str]:
    dt_min = d.time.replace(second=0, microsecond=0)
    deal_time = minute_str_local_ea(dt_min)
    return [
        day_date,
        str(konto),
        str(session_id),
        deal_time,
        d.ticket,
        d.symbol,
        d.direction,
        pl_lot(d.volume),
        pl_num(d.price, 2),
        pl_num(d.profit, 2),
        pl_num(0.0, 2),  # max_session_equity_drawdown — brak z HTML
        pl_num(session_profit_total, 2),  # jak w EA: suma sesji na każdym wierszu
        pl_lot(session_max_lot),
        pl_num(0.0, 2),  # max_margin_burned
        pl_num(0.0, 2) + "%",  # max_session_equity_burned_percent
        "",  # account_reset
        minute_start,
        minute_end,
    ]


def make_summary_row(
    konto: str,
    session_id: int,
    day_date: str,
    deals: List[HtmlDeal],
    minute_start: str,
    minute_end: str,
) -> List[str]:
    total_profit = sum(x.profit for x in deals)
    max_lot = max((x.volume for x in deals), default=0.0)
    start_b = ""
    end_b = ""
    if deals[0].balance_after is not None:
        # HTML zwykle ma Balance po każdym wierszu — przybliżenie końca
        end_b = pl_num(deals[-1].balance_after or 0.0, 2)
    return [
        day_date,
        str(konto),
        str(session_id),
        start_b,
        end_b,
        pl_num(0.0, 2),
        pl_num(total_profit, 2),
        pl_lot(max_lot),
        pl_lot(max_lot),
        pl_num(0.0, 2),
        pl_num(0.0, 2) + "%",
        "",
        minute_start,
        minute_end,
    ]


def default_insert_path(path: Path, suffix: str) -> Path:
    return path.with_name(path.stem + suffix + path.suffix)


def main() -> None:
    ap = argparse.ArgumentParser(
        description="INSERT brakujących danych do kopii CSV z raportu HTML MT5."
    )
    ap.add_argument("--html", required=True, type=Path, help="Plik .htm / .html z MT5")
    ap.add_argument("--konto", required=True, help="Login konta (jak w CSV)")
    ap.add_argument("--deals-in", type=Path, help="Wejściowy DailySessionDeals<konto>.csv")
    ap.add_argument("--summary-in", type=Path, help="Wejściowy DailySessionSummary.csv")
    ap.add_argument(
        "--deals-out",
        type=Path,
        help="Wyjście deals (domyślnie *_INSERT.csv obok deals-in)",
    )
    ap.add_argument(
        "--summary-out",
        type=Path,
        help="Wyjście summary (domyślnie *_INSERT.csv obok summary-in)",
    )
    ap.add_argument(
        "--insert-suffix",
        default="_INSERT",
        help="Przyrostek nazwy gdy --deals-out / --summary-out nie podano",
    )
    ap.add_argument(
        "--session-mode",
        choices=("day", "batch"),
        default="day",
        help="Jak grupować brakujące deale w syntetyczne sesje",
    )
    ap.add_argument("--dry-run", action="store_true", help="Tylko podsumowanie, bez zapisu")
    ap.add_argument(
        "--layout",
        choices=("deals-default", "positions-pl"),
        default="deals-default",
        help="deals-default=typowy eksport Deals (EN); positions-pl=Raport Historii PL sekcja Pozycje",
    )
    ap.add_argument("--col-time", type=int, default=None)
    ap.add_argument("--col-ticket", type=int, default=None)
    ap.add_argument("--col-symbol", type=int, default=None)
    ap.add_argument("--col-type", type=int, default=None)
    ap.add_argument("--col-volume", type=int, default=None)
    ap.add_argument("--col-price", type=int, default=None)
    ap.add_argument("--col-profit", type=int, default=None)
    ap.add_argument("--col-balance", type=int, default=None)
    ap.add_argument("--min-cols", type=int, default=None)
    args = ap.parse_args()
    konto = str(args.konto).strip()

    # Domyślne mapowanie kolumn wg layoutu (nadpisywalne --col-*)
    read_balance = True
    if args.layout == "deals-default":
        c_time, c_ticket, c_sym, c_typ = 0, 1, 2, 3
        c_vol, c_prc, c_prof, c_bal = 5, 6, -2, -1
        min_c = 8
    else:
        # positions-pl: czas zamknięcia w kol. 9; cena zamknięcia 10; zysk 13; brak salda
        c_time, c_ticket, c_sym, c_typ = 9, 1, 2, 3
        c_vol, c_prc, c_prof, c_bal = 5, 10, 13, -1
        min_c = 14
        read_balance = False

    col_time = args.col_time if args.col_time is not None else c_time
    col_ticket = args.col_ticket if args.col_ticket is not None else c_ticket
    col_symbol = args.col_symbol if args.col_symbol is not None else c_sym
    col_type = args.col_type if args.col_type is not None else c_typ
    col_volume = args.col_volume if args.col_volume is not None else c_vol
    col_price = args.col_price if args.col_price is not None else c_prc
    col_profit = args.col_profit if args.col_profit is not None else c_prof
    col_balance = args.col_balance if args.col_balance is not None else c_bal
    min_cols = args.min_cols if args.min_cols is not None else min_c

    html_text = read_path_mt5_text(args.html)
    html_deals = parse_deals_from_mt5_html(
        html_text,
        col_time=col_time,
        col_ticket=col_ticket,
        col_symbol=col_symbol,
        col_type=col_type,
        col_volume=col_volume,
        col_price=col_price,
        col_profit=col_profit,
        col_balance=col_balance,
        min_cols=min_cols,
        read_balance=read_balance,
    )
    if not html_deals:
        print(
            "UWAGA: z HTML nie wyciągnięto żadnych wierszy buy/sell. "
            "Sprawdź eksport (język kolumn) i ustaw --col-* oraz --min-cols.",
            file=sys.stderr,
        )

    written_any = False

    if args.deals_in:
        sep_d, drows = read_sem_csv_rows(args.deals_in)
        if not drows:
            raise SystemExit("--deals-in: pusty plik")
        validate_header(drows[0], EXPECTED_DEALS_COLS, "deals nagłówek")
        tickets = existing_deal_tickets(drows)
        missing = [d for d in html_deals if d.ticket not in tickets]
        base_sid = max_session_id_for_konto(drows, konto)
        sessions = build_synthetic_sessions(missing, args.session_mode, base_sid)

        new_rows: List[List[str]] = []
        for _gkey, (sid, gdeals) in sorted(
            sessions.items(), key=lambda x: x[1][0]
        ):
            if not gdeals:
                continue
            day_date = date_str_ea(gdeals[0].time)
            total_p = sum(x.profit for x in gdeals)
            max_lot = max(x.volume for x in gdeals)
            t0 = gdeals[0].time.replace(second=0, microsecond=0)
            t1 = gdeals[-1].time.replace(second=0, microsecond=0)
            ms = minute_str_local_ea(t0)
            me = minute_str_local_ea(t1)
            for d in gdeals:
                new_rows.append(
                    make_deal_csv_row(
                        d,
                        konto,
                        sid,
                        total_p,
                        max_lot,
                        ms,
                        me,
                        day_date,
                    )
                )

        out_deals = args.deals_out or default_insert_path(
            args.deals_in, args.insert_suffix
        )
        print(
            f"Deals: HTML={len(html_deals)} istniejących ticketów={len(tickets)} "
            f"do dopisania={len(new_rows)} -> {out_deals}"
        )
        if new_rows and not args.dry_run:
            # Zachowaj sep= z oryginału lub domyślny
            sep_use = sep_d if sep_d else "sep=;"
            # Upewnij się, że nagłówek zgodny ze schematem EA
            header = drows[0]
            new_rows.sort(
                key=lambda r: (
                    r[0],
                    r[3],
                    int(r[4].strip()) if r[4].strip().isdigit() else 0,
                )
            )
            write_sem_csv(out_deals, sep_use, [header] + drows[1:] + new_rows)
            written_any = True

    if args.summary_in:
        sep_s, srows = read_sem_csv_rows(args.summary_in)
        if not srows:
            raise SystemExit("--summary-in: pusty plik")
        validate_header(srows[0], EXPECTED_SUMMARY_COLS, "summary nagłówek")
        keys = summary_keys(srows)

        if not args.deals_in:
            raise SystemExit("Dla --summary-in podaj też --deals-in (ta sama logika insertu).")
        sep_d2, drows2 = read_sem_csv_rows(args.deals_in)
        tickets2 = existing_deal_tickets(drows2)
        missing2 = [d for d in html_deals if d.ticket not in tickets2]
        base_sid2 = max_session_id_for_konto(drows2, konto)
        sessions2 = build_synthetic_sessions(missing2, args.session_mode, base_sid2)

        sum_new: List[List[str]] = []
        for gkey, (sid, gdeals) in sorted(
            sessions2.items(), key=lambda x: x[1][0]
        ):
            if not gdeals:
                continue
            day_date = date_str_ea(gdeals[0].time)
            sk = (day_date, konto, str(sid))
            if sk in keys:
                continue
            t0 = gdeals[0].time.replace(second=0, microsecond=0)
            t1 = gdeals[-1].time.replace(second=0, microsecond=0)
            sum_new.append(
                make_summary_row(
                    konto,
                    sid,
                    day_date,
                    gdeals,
                    minute_str_local_ea(t0),
                    minute_str_local_ea(t1),
                )
            )
            keys.add(sk)

        out_sum = args.summary_out or default_insert_path(
            args.summary_in, args.insert_suffix
        )
        print(
            f"Summary: nowe wiersze sesji (syntetyczne)={len(sum_new)} -> {out_sum}"
        )
        if sum_new and not args.dry_run:
            sep_use = sep_s if sep_s else "sep=;"
            write_sem_csv(out_sum, sep_use, [srows[0]] + srows[1:] + sum_new)
            written_any = True

    if not args.deals_in and not args.summary_in:
        raise SystemExit("Podaj --deals-in i/lub --summary-in (summary wymaga deals-in).")

    if args.dry_run:
        print("Dry-run: brak zapisu plików.")
    elif not written_any:
        print("Nic nie zapisano (brak brakujących deali lub tylko dry-run).")


if __name__ == "__main__":
    main()
