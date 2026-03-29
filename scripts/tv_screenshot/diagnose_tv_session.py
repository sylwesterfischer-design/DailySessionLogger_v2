"""
Szybki test: czy Playwright + storage_state widzi stronę jak „normalna” sesja.

Sprawdza m.in. navigator.webdriver oraz tekst strony pod kątem trybu podglądu (PL/EN).
Nie łączy się z API TradingView — tylko przeglądarka.

Z rootu repo:
  .\\.venv\\Scripts\\python scripts\\tv_screenshot\\diagnose_tv_session.py
  .\\.venv\\Scripts\\python scripts\\tv_screenshot\\diagnose_tv_session.py --headed
  .\\.venv\\Scripts\\python scripts\\tv_screenshot\\diagnose_tv_session.py --chrome --headed
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

from screenshot_tv import CHROMIUM_LAUNCH_ARGS

_SCRIPT_DIR = Path(__file__).resolve().parent
# Jak scheduled_screenshots.py: plik leży w .../repo/scripts/tv_screenshot/*.py
_REPO_ROOT = Path(__file__).resolve().parents[2]


def _strip_comment_keys(obj: dict) -> dict:
    return {k: v for k, v in obj.items() if not str(k).startswith("_")}


def _load_schedule() -> dict:
    p = _SCRIPT_DIR / "capture_schedule.json"
    if not p.is_file():
        return {}
    with p.open(encoding="utf-8") as f:
        return _strip_comment_keys(json.load(f))


def main() -> int:
    ap = argparse.ArgumentParser(description="Diagnostyka sesji TradingView w Playwright.")
    ap.add_argument(
        "--url",
        default="",
        help="Pełny URL wykresu (domyślnie: chart_url_template z capture_schedule + interval=1).",
    )
    ap.add_argument(
        "--storage-state",
        default="",
        help="Plik storage_state JSON (domyślnie: klucz storage_state z capture_schedule).",
    )
    ap.add_argument(
        "--headed",
        action="store_true",
        help="Okno widoczne. Domyślnie headless=true (jak domyślny harmonogram).",
    )
    ap.add_argument(
        "--chrome",
        action="store_true",
        help="Zainstalowany Google Chrome (channel=chrome) zamiast bundled Chromium.",
    )
    ap.add_argument(
        "--wait-ms",
        type=int,
        default=8000,
        help="Czekanie po domcontentloaded (ms), żeby Pine zdążył się zainicjować.",
    )
    args = ap.parse_args()

    cfg = _load_schedule()
    url = (args.url or "").strip()
    if not url:
        tpl = cfg.get(
            "chart_url_template",
            "https://pl.tradingview.com/chart/PoqvuZcl/?interval={tv_interval}",
        )
        url = tpl.format(tv_interval="1")

    ss_arg = (args.storage_state or "").strip()
    if ss_arg:
        p = Path(ss_arg)
        storage_path = p if p.is_absolute() else _REPO_ROOT / p
    else:
        ss_rel = cfg.get("storage_state", "scripts/tv_screenshot/tv_storage_state.json")
        p = Path(ss_rel)
        storage_path = p if p.is_absolute() else _REPO_ROOT / p

    if not storage_path.is_file():
        print("BRAK pliku storage_state:", storage_path.resolve(), file=sys.stderr)
        return 2

    headless = not args.headed
    out: dict = {
        "url": url,
        "storage_state": str(storage_path.resolve()),
        "storage_state_bytes": storage_path.stat().st_size,
        "headless": headless,
        "chrome_channel": bool(args.chrome),
        "launch_args": list(CHROMIUM_LAUNCH_ARGS),
    }

    with sync_playwright() as pw:
        launch_kw: dict = {"headless": headless, "args": CHROMIUM_LAUNCH_ARGS}
        if args.chrome:
            browser = pw.chromium.launch(channel="chrome", **launch_kw)
        else:
            browser = pw.chromium.launch(**launch_kw)
        ctx = browser.new_context(
            viewport={"width": 1920, "height": 1080},
            storage_state=str(storage_path),
        )
        cookies = ctx.cookies()
        out["cookie_count_total"] = len(cookies)
        out["cookie_count_tradingview"] = sum(
            1 for c in cookies if "tradingview" in (c.get("domain") or "").lower()
        )
        page = ctx.new_page()
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=120_000)
            page.wait_for_timeout(int(args.wait_ms))

            nav = page.evaluate(
                """() => ({
                    webdriver: navigator.webdriver,
                    ua: navigator.userAgent,
                })"""
            )
            hints = page.evaluate(
                """() => {
                  const t = (document.body && document.body.innerText) || '';
                  return {
                    pl_preview_banner: /tryb\\s+podgl[aą]du/i.test(t),
                    en_preview: /preview\\s+mode/i.test(t),
                  };
                }"""
            )
            ua = nav.get("ua") or ""
            out["navigator_webdriver"] = nav.get("webdriver")
            out["user_agent_prefix"] = ua[:160]
            out["user_agent_contains_headless_chrome"] = "HeadlessChrome" in ua
            out["page_text_hints"] = hints
        finally:
            page.close()
            ctx.close()
            browser.close()

    out["interpretacja"] = (
        "Gdy user_agent_contains_headless_chrome=true (domyślny headless), TradingView "
        "może ograniczać Pine — ustaw w capture_schedule.json \"headed\": true i porównaj PNG. "
        "Skrypty zaproszeniowe wymagają aktywnego dostępu na koncie niezależnie od Playwright."
    )
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
