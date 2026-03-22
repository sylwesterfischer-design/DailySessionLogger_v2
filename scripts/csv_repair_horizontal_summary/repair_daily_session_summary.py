#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Naprawa poziomego „rozjechania” wierszy DailySessionSummary.csv (semicolon CSV):
powtórzenia tego samego bloku 14 kolumn w jednej linii fizycznej — zostawiamy pierwszy blok.

Użycie (PowerShell, z korzenia repo):
  python scripts/csv_repair_horizontal_summary/repair_daily_session_summary.py -i "C:\...\Common\Files\DailySessionSummary.csv" --backup
  python scripts/csv_repair_horizontal_summary/repair_daily_session_summary.py -i plik.csv -o plik_naprawiony.csv --dry-run

Opcjonalnie tylko wiersze pasujące do daty/konta (reszta linii bez zmian):
  python ... -i plik.csv --only-date 2026-03-20 --only-konto 11693814

Ta zmiana NIE zmienia definicji pliku (nadal 14 kolumn danych + sep=; + nagłówek).
"""
import argparse
import csv
import io
import shutil
import sys
from pathlib import Path
from typing import List, Optional, Tuple

EXPECTED_COLS = 14


def strip_bom(s: str) -> str:
    if s.startswith("\ufeff"):
        return s[1:]
    return s


def repair_fields(fields: List[str]) -> Tuple[List[str], int]:
    """
    Usuń powtórzenia bloków po EXPECTED_COLS kolumn.
    Zwraca (nowe_pola, liczba_usunietych_kolumn).
    """
    orig_len = len(fields)
    f = list(fields)
    removed = 0
    while len(f) >= 2 * EXPECTED_COLS:
        a = f[:EXPECTED_COLS]
        b = f[EXPECTED_COLS : 2 * EXPECTED_COLS]
        if a == b:
            f = f[:EXPECTED_COLS] + f[2 * EXPECTED_COLS :]
            removed += EXPECTED_COLS
        else:
            break
    if len(f) > EXPECTED_COLS:
        removed += len(f) - EXPECTED_COLS
        f = f[:EXPECTED_COLS]
    return f, removed


def line_matches_filter(
    fields: List[str], only_date: Optional[str], only_konto: Optional[str]
) -> bool:
    if not only_date and not only_konto:
        return True
    if len(fields) < 2:
        return False
    d = fields[0].strip()
    k = fields[1].strip()
    if only_date and d != only_date:
        return False
    if only_konto and k != only_konto:
        return False
    return True


def process_file(
    path_in: Path,
    path_out: Path,
    *,
    only_date: Optional[str],
    only_konto: Optional[str],
    dry_run: bool,
) -> tuple[int, int, int]:
    """
    Zwraca (linie_przetworzone, linie_naprawione, kolumny_usuniete_lacznie).
    """
    raw = path_in.read_text(encoding="utf-8-sig", errors="replace")
    raw = strip_bom(raw)

    out_lines: list[str] = []
    fixed_rows = 0
    cols_removed_total = 0
    rows_touched = 0

    for physical_line in raw.splitlines():
        line = physical_line.strip("\r\n")
        if not line:
            out_lines.append("")
            continue
        # sep=; i nagłówek — kopiujemy bez zmian
        if line.startswith("sep="):
            out_lines.append(line)
            continue
        if "date" in line.lower() and "konto" in line.lower() and "session_id" in line.lower():
            out_lines.append(line)
            continue

        # Parsujemy jako CSV z separatorem ;
        reader = csv.reader(io.StringIO(line), delimiter=";", quotechar='"')
        try:
            row = next(reader)
        except StopIteration:
            out_lines.append(line)
            continue

        if not row:
            out_lines.append(line)
            continue

        rows_touched += 1
        if len(row) <= EXPECTED_COLS:
            out_lines.append(line)
            continue

        if not line_matches_filter(row, only_date, only_konto):
            out_lines.append(line)
            continue

        new_row, removed = repair_fields(row)
        if removed > 0:
            fixed_rows += 1
            cols_removed_total += removed

        buf = io.StringIO()
        writer = csv.writer(buf, delimiter=";", quoting=csv.QUOTE_MINIMAL, lineterminator="")
        writer.writerow(new_row)
        out_lines.append(buf.getvalue())

    text_out = "\r\n".join(out_lines) + ("\r\n" if raw.endswith(("\n", "\r\n")) else "")

    if not dry_run:
        path_out.parent.mkdir(parents=True, exist_ok=True)
        path_out.write_text(text_out, encoding="utf-8-sig", newline="")

    return rows_touched, fixed_rows, cols_removed_total


def main() -> int:
    ap = argparse.ArgumentParser(description="Repair horizontal duplication in DailySessionSummary.csv")
    ap.add_argument("-i", "--input", required=True, type=Path, help="Ścieżka do DailySessionSummary.csv")
    ap.add_argument("-o", "--output", type=Path, default=None, help="Wyjście (domyślnie: nadpisz wejście jeśli --backup)")
    ap.add_argument("--backup", action="store_true", help="Przed zapisem skopiuj wejście do .bak (tylko gdy -o nie podano)")
    ap.add_argument("--dry-run", action="store_true", help="Tylko raport, nie zapisuj pliku")
    ap.add_argument("--only-date", type=str, default=None, help="Naprawiaj tylko wiersze z tą kolumną date (np. 2026-03-20)")
    ap.add_argument("--only-konto", type=str, default=None, help="Naprawiaj tylko wiersze z tym konto (np. 11693814)")
    args = ap.parse_args()

    path_in = args.input.resolve()
    if not path_in.is_file():
        print(f"BŁĄD: brak pliku: {path_in}", file=sys.stderr)
        return 2

    path_out = args.output
    if path_out is None:
        path_out = path_in
    else:
        path_out = path_out.resolve()

    if args.backup and not args.dry_run and args.output is None:
        bak = path_in.with_suffix(path_in.suffix + ".bak")
        shutil.copy2(path_in, bak)
        print(f"Backup: {bak}")

    touched, fixed, removed = process_file(
        path_in,
        path_out,
        only_date=args.only_date,
        only_konto=args.only_konto,
        dry_run=args.dry_run,
    )

    print(f"Linii danych rozpoznanych (poza nagłówkiem/sep): {touched}")
    print(f"Wierszy naprawionych (było >{EXPECTED_COLS} kolumn / powtórzenia): {fixed}")
    print(f"Usuniętych nadmiarowych „kolumn” łącznie: {removed}")
    if args.dry_run:
        print("DRY-RUN — plik nie został zapisany.")
    else:
        print(f"Zapisano: {path_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
