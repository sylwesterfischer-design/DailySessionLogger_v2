"""
Jednorazowo: otwiera przeglądarkę (headed), czekasz aż zalogujesz się na tradingview.com,
potem Enter — zapisuje cookies do pliku (Playwright storage state).

Opcjonalnie: --chrome  →  zainstalowany Google Chrome (Playwright channel=chrome); często lepsze CAPTCHA niż bundled Chromium.

Plik użyj w capture_schedule.json jako "storage_state" albo:
  screenshot_tv.py --storage-state scripts/tv_screenshot/tv_storage_state.json

Log: scripts/tv_screenshot/tv_save_session.log (harmonogram zrzutów: docs/tv_scheduled/tv_capture.log)

Nie commituj tv_storage_state.json (zawiera sesję).
"""
from __future__ import annotations

import logging
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

from screenshot_tv import CHROMIUM_LAUNCH_ARGS

_SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_OUT = _SCRIPT_DIR / "tv_storage_state.json"
LOG_FILE = _SCRIPT_DIR / "tv_save_session.log"


def _setup_logging() -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter(
        "%(asctime)sZ %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    fmt.converter = time.gmtime
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    root.handlers.clear()
    fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
    fh.setFormatter(fmt)
    root.addHandler(fh)
    if sys.stderr and getattr(sys.stderr, "isatty", lambda: False)():
        sh = logging.StreamHandler(sys.stderr)
        sh.setFormatter(fmt)
        sh.setLevel(logging.INFO)
        root.addHandler(sh)


_log = logging.getLogger("save_tv_storage_state")

def _attach_page_logging(page, label: str) -> None:
    def on_console(msg) -> None:
        if msg.type in ("error", "warning"):
            _log.warning("console[%s] %s: %s", label, msg.type, msg.text)
        else:
            _log.debug("console[%s] %s: %s", label, msg.type, msg.text)

    page.on("console", on_console)
    page.on("pageerror", lambda exc: _log.warning("pageerror[%s] %s", label, exc))


def _parse_out_and_chrome_flag() -> tuple[Path, bool]:
    raw = [a for a in sys.argv[1:] if a != "--chrome"]
    use_chrome = "--chrome" in sys.argv[1:]
    out = Path(raw[0]) if raw else DEFAULT_OUT
    return out, use_chrome


def main() -> int:
    _setup_logging()
    out, use_chrome_channel = _parse_out_and_chrome_flag()

    _log.info(
        "START save_tv_storage_state out=%s log=%s use_chrome_channel=%s",
        out.resolve(),
        LOG_FILE.resolve(),
        use_chrome_channel,
    )
    _log.info(
        "Okno = %s",
        "Google Chrome (channel=chrome)" if use_chrome_channel else "Chromium bundled Playwright",
    )

    if use_chrome_channel:
        print(
            "Tryb --chrome: zainstalowany Google Chrome (często lepsze CAPTCHA niż bundled Chromium).",
            flush=True,
        )
    else:
        print(
            "Otwieram Chromium od Playwrighta (bundled z ms-playwright) — wygląda jak Chrome, "
            "to NIE jest Twój zainstalowany Google Chrome ani profil z Chrome.",
            flush=True,
        )
        print(
            "Przy problemie z CAPTCHA na TV spróbuj: "
            ".\.venv\Scripts\python scripts\tv_screenshot\save_tv_storage_state.py --chrome",
            flush=True,
        )
    print(
        "Zaloguj się na TradingView (to samo konto co zapisany layout).",
        flush=True,
    )
    print(
        "WAŻNE: po zalogowaniu otwórz TEN SAM wykres co w zrzutach (np. twój link /chart/...), "
        "zaakceptuj cookies, sprawdź że wskaźniki ładują się BEZ czerwonych wykrzykników.",
        flush=True,
    )
    print("Następnie naciśnij Enter tutaj, aby zapisać sesję do:", out, flush=True)
    print("Log zapisu sesji:", LOG_FILE.resolve(), flush=True)
    print(
        "Uwaga: „Continue with Google” często zostawia puste okno (about:blank) — Google ogranicza "
        "OAuth w zautomatyzowanym Chromium. Lepiej: zaloguj się przez e-mail/hasło na TradingView "
        "(to samo konto). Żółty pasek „Debugger wstrzymany” — wznów (F8) lub zamknij DevTools.",
        flush=True,
    )

    try:
        with sync_playwright() as pw:
            _log.info(
                "Playwright: headless=False use_chrome_channel=%s args=%s",
                use_chrome_channel,
                CHROMIUM_LAUNCH_ARGS,
            )
            if use_chrome_channel:
                browser = pw.chromium.launch(
                    channel="chrome",
                    headless=False,
                    args=CHROMIUM_LAUNCH_ARGS,
                )
            else:
                browser = pw.chromium.launch(
                    headless=False,
                    args=CHROMIUM_LAUNCH_ARGS,
                )
            context = browser.new_context(viewport={"width": 1400, "height": 900})

            def _on_new_page(p) -> None:
                _log.info("Nowe okno/karta (np. OAuth): url=%s", p.url)
                _attach_page_logging(p, "popup")

            context.on("page", _on_new_page)
            page = context.new_page()
            _attach_page_logging(page, "main")
            _log.info("goto https://www.tradingview.com/ ...")
            page.goto("https://www.tradingview.com/", timeout=120_000)
            _log.info(
                "Strona startowa załadowana. Zaloguj się w oknie przeglądarki, "
                "potem Enter w terminalu."
            )
            input()
            _log.info("Enter — zapisuję storage_state ...")
            context.storage_state(path=str(out))
            page.close()
            context.close()
            browser.close()

        _log.info("Zapisano storage_state: %s bytes=%s", out.resolve(), out.stat().st_size)
        print("Zapisano:", out.resolve(), flush=True)
        return 0
    except Exception:
        _log.exception("BŁĄD — nie udało się zapisać sesji")
        print("BŁĄD — szczegóły w:", LOG_FILE.resolve(), flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
