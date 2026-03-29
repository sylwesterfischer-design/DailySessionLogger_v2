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
  • `--layout positions-pl`: rekonstrukcja sesji jak w EA (licznik pozycji: +1 przy
    czasie otwarcia kol. 0, −1 przy zamknięciu kol. 9), osobno na każdy dzień
    kalendarzowy (czas z komórek HTML = czas serwera MT5 z raportu).
  • `--layout deals-default`: brak czasu otwarcia w wierszu — tylko sesje syntetyczne
    (--session-mode day lub batch).
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

  # Tylko jeden dzień z dużego HTML (data z kolumny czasu deala):
  py scripts/csv_insert_from_mt5_html/insert_from_mt5_html.py ... --only-date 2026-03-18

  # Pasek postępu w CMD: domyślnie włączony (stderr); opcjonalnie: pip install tqdm
  # Wyłączenie: --no-progress
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
from typing import Any, Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple

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


def normalize_only_date_arg(s: str) -> str:
    """Walidacja `--only-date` (kalendarz wg czasu z komórki HTML, jak `date_str_ea`)."""
    t = s.strip()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", t):
        raise SystemExit("--only-date: oczekiwano YYYY-MM-DD (np. 2026-03-18)")
    return t


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
    """Wyciąga teksty komórek <td>...</td> dla każdego <tr> (strumieniowo — bez listy wszystkich <tr> naraz)."""
    for m in re.finditer(r"<tr[^>]*>(.*?)</tr>", html, flags=re.I | re.S):
        tr = m.group(1)
        cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, flags=re.I | re.S)
        if not cells:
            continue
        yield [clean_cell(c) for c in cells]


def approx_table_row_count(html: str) -> int:
    """Przybliżona liczba wierszy <tr> w HTML (do skali paska postępu; szybkie, bez pełnego regexa)."""
    return html.lower().count("<tr")


def iter_with_stderr_progress(
    iterable: Iterable[List[str]],
    *,
    desc: str,
    total_hint: Optional[int],
    enabled: bool,
) -> Iterator[List[str]]:
    """
    Pasek postępu na stderr w interaktywnym CMD (gdy stderr jest TTY).
    Jeśli zainstalowane jest `tqdm`, używa go; w przeciwnym razie prosty %.
    Przy przekierowaniu do pliku (np. `>> log.txt`) — bez paska.
    """
    if not enabled:
        yield from iterable
        return
    it = iter(iterable)
    if not sys.stderr.isatty():
        yield from it
        return
    tqdm: Any
    try:
        from tqdm import tqdm as tqdm_cls  # type: ignore[import-not-found]

        tqdm = tqdm_cls
    except ImportError:
        tqdm = None
    if tqdm is not None:
        yield from tqdm(
            it,
            total=total_hint,
            desc=desc,
            file=sys.stderr,
            unit="wiersz",
            mininterval=0.25,
            dynamic_ncols=True,
            ascii=True,
        )
        return
    n = 0
    last_pct = -1
    for item in it:
        n += 1
        if total_hint and total_hint > 0:
            pct = min(100, int(100.0 * n / total_hint))
            if pct != last_pct or n <= 1:
                last_pct = pct
                sys.stderr.write(f"\r{desc} {n}/{total_hint} ({pct}%)   ")
                sys.stderr.flush()
        elif n % 2000 == 0 or n == 1:
            sys.stderr.write(f"\r{desc} {n} wierszy...   ")
            sys.stderr.flush()
        yield item
    sys.stderr.write("\r" + " " * 78 + "\r")
    sys.stderr.flush()


@dataclass
class HtmlDeal:
    # time = czas zamknięcia pozycji (jak deal_time w CSV EA); open_time = z HTML kol. „Czas” otwarcia (positions-pl)
    time: datetime
    ticket: str
    symbol: str
    direction: str  # buy / sell
    volume: float
    price: float
    profit: float
    balance_after: Optional[float]
    open_time: Optional[datetime] = None


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
    show_progress: bool = True,
    only_date_ymd: Optional[str] = None,
) -> Tuple[List[HtmlDeal], int]:
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

    Zwraca (lista deali, liczba przetworzonych wierszy <tr>).
    Gdy podano ``only_date_ymd`` (YYYY-MM-DD), odrzuca wiersze po dacie zamknięcia
    zanim zrobi cięższe sprawdzenia — duży raport HTML jest wtedy znacznie szybszy.
    """
    deals: List[HtmlDeal] = []
    tr_rows = 0
    total_hint = approx_table_row_count(html_text) if show_progress else None
    row_iter: Iterable[List[str]] = iter_table_rows(html_text)
    if show_progress:
        row_iter = iter_with_stderr_progress(
            row_iter,
            desc="Parsowanie HTML",
            total_hint=total_hint,
            enabled=True,
        )
    for cells in row_iter:
        tr_rows += 1
        n = len(cells)
        if n < min_cols:
            continue

        def idx(i: int) -> int:
            return i if i >= 0 else n + i

        t_close: Optional[datetime] = None
        if only_date_ymd is not None:
            ci = idx(col_time)
            if ci < 0 or ci >= n:
                continue
            t_close = parse_mt5_html_datetime(cells[ci])
            if t_close is None:
                continue
            if date_str_ea(t_close) != only_date_ymd:
                continue

        if not row_looks_like_deal(cells, min_cols):
            continue

        # Czas zamknięcia (deal_time) — kol. col_time; dla positions-pl (col_time=9) czas otwarcia w kol. 0
        open_time: Optional[datetime] = None
        if col_time != 0:
            ot = parse_mt5_html_datetime(cells[0])
            if ot is not None:
                open_time = ot
        if t_close is not None:
            t = t_close
        else:
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
                open_time=open_time,
            )
        )
    # Stabilny porządek: czas, ticket
    deals.sort(key=lambda d: (d.time, int(d.ticket)))
    return deals, tr_rows


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


def existing_deal_tickets_for_date(
    deals_rows: List[List[str]], konto: str, ymd: Optional[str]
) -> Set[str]:
    """
    Zbiór ticketów z istniejącego deals CSV dla wybranego konta i dnia.
    deals_time w CSV ma format DD.MM.YYYY HH:MM.
    """
    if not ymd:
        return existing_deal_tickets(deals_rows)
    out: Set[str] = set()
    for r in deals_rows[1:]:
        if len(r) < 5:
            continue
        if r[1].strip() != str(konto):
            continue
        deal_time = r[3].strip()
        m = re.match(r"^(\d{2})\.(\d{2})\.(\d{4})\s+\d{2}:\d{2}$", deal_time)
        if not m:
            continue
        dd, mm, yy = m.groups()
        row_ymd = f"{yy}-{mm}-{dd}"
        if row_ymd == ymd:
            out.add(r[4].strip())
    return out


def max_session_id_for_konto(rows: List[List[str]], konto: str) -> int:
    m = 0
    for r in rows[1:]:
        if len(r) < 3:
            continue
        if r[1].strip() != str(konto):
            continue
        sid = parse_excel_int(r[2].strip())
        if sid is None:
            continue
        m = max(m, sid)
    return m


def summary_keys(rows: List[List[str]]) -> Set[Tuple[str, str, str]]:
    keys: Set[Tuple[str, str, str]] = set()
    for r in rows[1:]:
        if len(r) < 3:
            continue
        raw_d = r[0].strip()
        d_key = summary_cell_date_to_ymd(raw_d) or raw_d
        sid_norm = parse_excel_int(r[2].strip())
        sid_key = str(sid_norm) if sid_norm is not None else r[2].strip()
        keys.add((d_key, r[1].strip(), sid_key))
    return keys


def ymd_to_int(ymd: str) -> Optional[int]:
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", ymd.strip())
    if not m:
        return None
    y, mo, d = m.groups()
    return int(f"{y}{mo}{d}")


def summary_cell_date_to_ymd(cell: str) -> Optional[str]:
    """
    Normalizacja kolumny ``date`` w DailySessionSummary (jak w Excel / eksport MT5):
    ``YYYY-MM-DD`` (jak ``date_str_ea``) albo ``DD.MM.YYYY``.
    """
    s = cell.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        return s
    m = re.fullmatch(r"(\d{2})\.(\d{2})\.(\d{4})", s)
    if m:
        dd, mm, yy = m.groups()
        return f"{yy}-{mm}-{dd}"
    return None


def parse_excel_int(s: str) -> Optional[int]:
    """
    Obsługa liczb zapisanych jako tekst przez Excela/MT5:
    - czasem pojawia się apostrof wiodący, np. `'4`
    - czasem wartości mają dodatkowe znaki
    """
    t = s.strip()
    if not t:
        return None
    # Excel często prefiksuje liczby tekstowe apostrofem.
    if t.startswith("'"):
        t = t[1:].strip()
    m = re.search(r"[-+]?\d+", t)
    if not m:
        return None
    try:
        return int(m.group(0))
    except ValueError:
        return None


def previous_end_balance_for_day(
    summary_rows: List[List[str]], konto: str, day_ymd: str
) -> Optional[float]:
    """
    Znajdź ostatni znany end_balance dla konta z daty < day_ymd.
    Używane do rekonstrukcji start/end balance nowych sesji.
    Porównanie dat po znormalizowaniu (ISO oraz DD.MM.YYYY w pliku summary).
    """
    target = ymd_to_int(day_ymd)
    if target is None:
        return None
    best_date = -1
    best_sid = -1
    best_val: Optional[float] = None
    for r in summary_rows[1:]:
        if len(r) < 5:
            continue
        if r[1].strip() != str(konto):
            continue
        d_norm = summary_cell_date_to_ymd(r[0].strip())
        if d_norm is None:
            continue
        d_int = ymd_to_int(d_norm)
        if d_int is None or d_int >= target:
            continue
        sid = parse_excel_int(r[2].strip())
        end_raw = r[4].strip()
        if end_raw == "":
            continue
        end_val = parse_pl_number(end_raw)
        if sid is None:
            sid = -1
        if d_int > best_date or (d_int == best_date and sid > best_sid):
            best_date = d_int
            best_sid = sid
            best_val = end_val
    return best_val


def floor_minute(dt: datetime) -> datetime:
    """Jak FloorToMinute w EA: sekundy zerowane."""
    return dt.replace(second=0, microsecond=0)


def build_sessions_ea_flat_from_deals(
    deals: List[HtmlDeal], base_session_id: int
) -> List[Tuple[int, List[HtmlDeal], str, str]]:
    """
    Sesja jak w .cursorrules_General: start gdy liczba pozycji 0 -> >0, koniec przy flat (0).
    Symulacja z HTML „Pozycje”: +1 przy czasie otwarcia (kol. 0), -1 przy zamknięciu (kol. 9).
    Zwraca listę (session_id, deale w sesji, minute_session_start, minute_session_end).
    """
    if not deals:
        return []
    if any(d.open_time is None for d in deals):
        g = build_synthetic_sessions(deals, "day", base_session_id)
        out: List[Tuple[int, List[HtmlDeal], str, str]] = []
        for _k, (sid, gdeals) in sorted(g.items(), key=lambda x: x[1][0]):
            if not gdeals:
                continue
            sb = floor_minute(gdeals[0].time)
            se = floor_minute(gdeals[-1].time)
            out.append(
                (
                    sid,
                    sorted(gdeals, key=lambda x: (x.time, int(x.ticket))),
                    minute_str_local_ea(sb),
                    minute_str_local_ea(se),
                )
            )
        return out

    events: List[Tuple[datetime, int, str]] = []
    for d in deals:
        ot = floor_minute(d.open_time) if d.open_time else floor_minute(d.time)
        ct = floor_minute(d.time)
        events.append((ot, 1, d.ticket))
        events.append((ct, -1, d.ticket))
    # Ten sam timestamp: najpierw zamknięcia (-1), potem otwarcia (+1) — flat zanim startuje następna sesja
    events.sort(key=lambda x: (x[0], 0 if x[1] < 0 else 1))

    count = 0
    sess_start: Optional[datetime] = None
    sess_bounds: List[Tuple[datetime, datetime]] = []

    for t, delta, _ticket in events:
        prev = count
        count += delta
        if prev == 0 and count > 0:
            sess_start = t
        elif prev > 0 and count == 0 and sess_start is not None:
            se = t
            if se < sess_start:
                sess_start, se = se, sess_start
            sess_bounds.append((sess_start, se))
            sess_start = None

    if count > 0 and sess_start is not None:
        last_close = max(floor_minute(d.time) for d in deals)
        if last_close < sess_start:
            last_close = sess_start
        sess_bounds.append((sess_start, last_close))

    if not sess_bounds:
        g = build_synthetic_sessions(deals, "day", base_session_id)
        out: List[Tuple[int, List[HtmlDeal], str, str]] = []
        for _k, (sid, gdeals) in sorted(g.items(), key=lambda x: x[1][0]):
            if not gdeals:
                continue
            sb = floor_minute(gdeals[0].time)
            se = floor_minute(gdeals[-1].time)
            out.append(
                (
                    sid,
                    sorted(gdeals, key=lambda x: (x.time, int(x.ticket))),
                    minute_str_local_ea(sb),
                    minute_str_local_ea(se),
                )
            )
        return out

    groups: List[List[HtmlDeal]] = [[] for _ in sess_bounds]
    for d in deals:
        cd = floor_minute(d.time)
        placed = False
        for i, (sb, se) in enumerate(sess_bounds):
            if cd >= sb and cd <= se:
                groups[i].append(d)
                placed = True
                break
        if not placed and sess_bounds:
            groups[-1].append(d)

    result: List[Tuple[int, List[HtmlDeal], str, str]] = []
    next_sid = base_session_id + 1
    for (sb, se), gdeals in zip(sess_bounds, groups):
        if not gdeals:
            continue
        sid = next_sid
        next_sid += 1
        gdeals.sort(key=lambda x: (x.time, int(x.ticket)))
        result.append(
            (sid, gdeals, minute_str_local_ea(sb), minute_str_local_ea(se))
        )
    return result


def build_sessions_for_insert(
    deals: List[HtmlDeal],
    *,
    layout: str,
    session_mode: str,
    base_session_id: int,
) -> List[Tuple[int, List[HtmlDeal], str, str]]:
    """
    Jedna lista bloków sesji do zapisu deals + summary.
    • deals-default / batch: syntetyczne sesje (day lub batch).
    • positions-pl: per dzień kalendarzowy symulacja flat (0→pozycje→0), jak EA.
    """
    if not deals:
        return []
    if layout != "positions-pl":
        g = build_synthetic_sessions(deals, session_mode, base_session_id)
        out: List[Tuple[int, List[HtmlDeal], str, str]] = []
        for _k, (sid, gdeals) in sorted(g.items(), key=lambda x: x[1][0]):
            if not gdeals:
                continue
            t0 = gdeals[0].time.replace(second=0, microsecond=0)
            t1 = gdeals[-1].time.replace(second=0, microsecond=0)
            out.append(
                (sid, gdeals, minute_str_local_ea(t0), minute_str_local_ea(t1))
            )
        return out

    # positions-pl: nie mieszaj dni — osobna symulacja flat na każdy YYYY-MM-DD
    by_day: Dict[str, List[HtmlDeal]] = defaultdict(list)
    for d in deals:
        by_day[date_str_ea(d.time)].append(d)
    result: List[Tuple[int, List[HtmlDeal], str, str]] = []
    cur_base = base_session_id
    for day_key in sorted(by_day.keys()):
        day_deals = sorted(
            by_day[day_key], key=lambda x: (x.time, int(x.ticket))
        )
        part = build_sessions_ea_flat_from_deals(day_deals, cur_base)
        result.extend(part)
        if part:
            cur_base = max(sid for sid, _, _, _ in part)
    return result


def compute_session_max_total_lot(gdeals: List[HtmlDeal]) -> float:
    """
    Dokładny max_total_lot w sesji:
    suma wolumenów jednocześnie otwartych pozycji (open +vol, close -vol).
    """
    if not gdeals:
        return 0.0
    if any(d.open_time is None for d in gdeals):
        # Fallback dla layoutów bez czasu otwarcia.
        return max((d.volume for d in gdeals), default=0.0)

    events: List[Tuple[datetime, int, float]] = []
    for d in gdeals:
        ot = floor_minute(d.open_time) if d.open_time else floor_minute(d.time)
        ct = floor_minute(d.time)
        # Ten sam timestamp: najpierw close, potem open (spójne z sesjami flat).
        events.append((ct, 0, -abs(d.volume)))
        events.append((ot, 1, abs(d.volume)))
    events.sort(key=lambda x: (x[0], x[1]))

    current = 0.0
    max_seen = 0.0
    for _t, _ord, dv in events:
        current += dv
        # Ochrona przed drobnymi driftami i kolejnością skrajną.
        if current < 0:
            current = 0.0
        if current > max_seen:
            max_seen = current
    return max_seen


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
    start_balance: Optional[float],
    end_balance: Optional[float],
    max_total_lot: float,
) -> List[str]:
    total_profit = sum(x.profit for x in deals)
    max_lot = max((x.volume for x in deals), default=0.0)
    # Start/end balance: rekonstrukcja z poprzedniego dnia + kumulacja profitów sesji.
    start_b = "" if start_balance is None else pl_num(start_balance, 2)
    end_b = "" if end_balance is None else pl_num(end_balance, 2)
    return [
        day_date,
        str(konto),
        str(session_id),
        start_b,
        end_b,
        pl_num(0.0, 2),
        pl_num(total_profit, 2),
        pl_lot(max_lot),
        pl_lot(max_total_lot),
        pl_num(0.0, 2),
        pl_num(0.0, 2) + "%",
        "",
        minute_start,
        minute_end,
    ]


def default_insert_path(path: Path, suffix: str) -> Path:
    return path.with_name(path.stem + suffix + path.suffix)


def default_pytest_path(path: Path, kind: str, konto: str) -> Path:
    """
    Tryb testowy: generuj stabilne nazwy wyjściowe, żeby nie ruszać produkcyjnych CSV.
    - deals  -> DailySessionDeals<konto>_pyTEST.csv
    - summary-> DailySessionSummary_pyTEST.csv
    """
    if kind == "deals":
        return path.with_name(f"DailySessionDeals{konto}_pyTEST.csv")
    return path.with_name("DailySessionSummary_pyTEST.csv")


def main() -> None:
    # Stabilizuj kodowanie stdout/stderr pod Windows (cmd/cp1252),
    # aby logi z polskimi znakami nie wysypywały parsera podczas print().
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        # Starsze/interaktywne środowiska mogą nie wspierać reconfigure.
        pass

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
    # Tryb bezpieczny do porównania wyników parsera z HTML:
    # zapisuj wyłącznie do plików *_pyTEST.csv (bez nadpisywania produkcyjnych wejść).
    ap.add_argument(
        "--test-outputs",
        action="store_true",
        help="Domyślne wyjścia: DailySessionDeals<konto>_pyTEST.csv i DailySessionSummary_pyTEST.csv",
    )
    ap.add_argument(
        "--session-mode",
        choices=("day", "batch"),
        default="day",
        help="Jak grupować brakujące deale w syntetyczne sesje",
    )
    ap.add_argument("--dry-run", action="store_true", help="Tylko podsumowanie, bez zapisu")
    ap.add_argument(
        "--only-date",
        type=str,
        default=None,
        help="Filtruj deale z HTML do jednego dnia YYYY-MM-DD",
    )
    ap.add_argument(
        "--qa-report",
        action="store_true",
        help="Wypisz raport porównania jakości: HTML vs istniejący deals CSV",
    )
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
    ap.add_argument(
        "--no-progress",
        action="store_true",
        help="Wyłącz pasek postępu przy parsowaniu HTML (np. skrypty bez TTY)",
    )
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
    only_parse: Optional[str] = None
    if args.only_date is not None:
        only_parse = normalize_only_date_arg(args.only_date)
    html_deals, tr_scanned = parse_deals_from_mt5_html(
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
        show_progress=not args.no_progress,
        only_date_ymd=only_parse,
    )
    if only_parse is not None:
        print(
            f"Filtr --only-date={only_parse}: wierszy <tr> przetworzonych={tr_scanned} "
            f"-> dealow dla tego dnia={len(html_deals)}",
            file=sys.stderr,
        )
    if not html_deals:
        print(
            "UWAGA: z HTML nie wyciągnięto żadnych wierszy buy/sell. "
            "Sprawdź eksport (język kolumn) i ustaw --col-* oraz --min-cols.",
            file=sys.stderr,
        )

    written_any = False

    # Tryb testowy jest do walidacji konkretnego dnia, nie do hurtowego merge.
    if args.test_outputs and args.only_date is None:
        raise SystemExit("--test-outputs wymaga --only-date YYYY-MM-DD")

    if args.deals_in:
        sep_d, drows = read_sem_csv_rows(args.deals_in)
        if not drows:
            raise SystemExit("--deals-in: pusty plik")
        validate_header(drows[0], EXPECTED_DEALS_COLS, "deals nagłówek")
        tickets = existing_deal_tickets(drows)
        tickets_scope = existing_deal_tickets_for_date(drows, konto, args.only_date)
        html_tickets = {d.ticket for d in html_deals}
        if args.qa_report:
            common = html_tickets & tickets_scope
            html_only = html_tickets - tickets_scope
            csv_only = tickets_scope - html_tickets
            print(
                f"QA deals[{args.only_date or 'ALL'} konto={konto}]: "
                f"html={len(html_tickets)} csv_scope={len(tickets_scope)} "
                f"common={len(common)} html_only={len(html_only)} csv_only={len(csv_only)}"
            )
            if html_only:
                ex = ",".join(sorted(list(html_only))[:10])
                print(f"QA html_only sample: {ex}")
            if csv_only:
                ex = ",".join(sorted(list(csv_only))[:10])
                print(f"QA csv_only sample: {ex}")
        missing = [d for d in html_deals if d.ticket not in tickets]
        base_sid = max_session_id_for_konto(drows, konto)
        # positions-pl: sesje z symulacji flat (open/close z HTML); inaczej syntetyczne day/batch
        sessions = build_sessions_for_insert(
            missing,
            layout=args.layout,
            session_mode=args.session_mode,
            base_session_id=base_sid,
        )

        new_rows: List[List[str]] = []
        for sid, gdeals, ms, me in sessions:
            if not gdeals:
                continue
            day_date = date_str_ea(gdeals[0].time)
            total_p = sum(x.profit for x in gdeals)
            # max_total_lot = realna suma jednocześnie otwartych lotów w sesji.
            max_lot = compute_session_max_total_lot(gdeals)
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

        if args.deals_out:
            out_deals = args.deals_out
        elif args.test_outputs:
            # Tryb pyTEST: stabilna nazwa testowa per konto.
            out_deals = default_pytest_path(args.deals_in, "deals", konto)
        else:
            out_deals = default_insert_path(args.deals_in, args.insert_suffix)
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
            # Tryb pyTEST: zapis tylko wygenerowanych wierszy z HTML (bez pełnej kopii wejścia).
            if args.test_outputs:
                write_sem_csv(out_deals, sep_use, [header] + new_rows)
            else:
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
        sessions2 = build_sessions_for_insert(
            missing2,
            layout=args.layout,
            session_mode=args.session_mode,
            base_session_id=base_sid2,
        )

        sum_new: List[List[str]] = []
        # Grupuj sesje po dniu, aby odtworzyć start/end balance sekwencyjnie.
        sessions_by_day: Dict[str, List[Tuple[int, List[HtmlDeal], str, str]]] = defaultdict(list)
        for sid, gdeals, ms, me in sessions2:
            if not gdeals:
                continue
            sessions_by_day[date_str_ea(gdeals[0].time)].append((sid, gdeals, ms, me))

        for day_date in sorted(sessions_by_day.keys()):
            day_sessions = sorted(sessions_by_day[day_date], key=lambda x: x[0])
            # Start dnia = ostatni znany end_balance z wcześniejszej daty.
            day_balance = previous_end_balance_for_day(srows, konto, day_date)
            for sid, gdeals, ms, me in day_sessions:
                sk = (day_date, konto, str(sid))
                if sk in keys:
                    continue
                # max_session_profit w summary = suma profit_only deali sesji (jak w wierszach deals INSERT).
                max_session_profit = sum(x.profit for x in gdeals)
                start_b = day_balance
                end_b = (
                    (day_balance + max_session_profit)
                    if day_balance is not None
                    else None
                )
                sum_new.append(
                    make_summary_row(
                        konto,
                        sid,
                        day_date,
                        gdeals,
                        ms,
                        me,
                        start_b,
                        end_b,
                        compute_session_max_total_lot(gdeals),
                    )
                )
                # Następna sesja zaczyna od końca poprzedniej (jeśli mamy bazowy balans).
                if end_b is not None:
                    day_balance = end_b
                keys.add(sk)

        if args.summary_out:
            out_sum = args.summary_out
        elif args.test_outputs:
            # Tryb pyTEST: jedna nazwa testowa summary (globalny plik podsumowania).
            out_sum = default_pytest_path(args.summary_in, "summary", konto)
        else:
            out_sum = default_insert_path(args.summary_in, args.insert_suffix)
        print(
            f"Summary: nowe wiersze sesji={len(sum_new)} -> {out_sum}"
        )
        if sum_new and not args.dry_run:
            sep_use = sep_s if sep_s else "sep=;"
            # Tryb pyTEST: zapis tylko nowo wygenerowanych podsumowań sesji.
            if args.test_outputs:
                write_sem_csv(out_sum, sep_use, [srows[0]] + sum_new)
            else:
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
