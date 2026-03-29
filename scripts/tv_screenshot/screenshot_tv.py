"""
Minimalny zrzut viewportu (np. wykres TradingView) przez Playwright + Chromium.

URL musi być **linkiem do wykresu** (najlepiej zapisany layout z konta), nie stroną /v/... skryptu.
Opcjonalnie: --storage-state (plik z cookies po save_tv_storage_state.py).

Uruchomienie z rootu repo (Windows):
  .\\.venv\\Scripts\\python scripts\\tv_screenshot\\screenshot_tv.py --url "https://..."
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from playwright.sync_api import Browser, BrowserContext, Page, sync_playwright

# Wspólne dla save_tv_storage_state + scheduled_screenshots — bez tego TV częściej
# wykrywa automatyzację (headless + nagłówek), co daje tryb podglądu / błędy Pine.
CHROMIUM_LAUNCH_ARGS: list[str] = [
    "--disable-popup-blocking",
    "--disable-blink-features=AutomationControlled",
]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def capture_screenshot(
    url: str,
    out: Path,
    *,
    width: int = 1920,
    height: int = 1080,
    wait_ms: int = 8000,
    headed: bool = False,
    full_page: bool = False,
    browser: Browser | None = None,
    browser_context: BrowserContext | None = None,
    storage_state: str | Path | None = None,
) -> Path:
    """
    Jeśli `browser_context` — tylko nowa strona w tym kontekście (np. zalogowany layout).
    Jeśli `browser` bez kontekstu — tworzy tymczasowy kontekst (opcjonalnie storage_state).
    Jeśli oba None — jednorazowy Chromium + kontekst.
    """
    out.parent.mkdir(parents=True, exist_ok=True)

    if browser_context is not None:
        _do_capture_context(
            browser_context, url, out, width, height, wait_ms, full_page
        )
        return out.resolve()

    if browser is not None:
        ctx = browser.new_context(
            viewport={"width": width, "height": height},
            storage_state=str(storage_state) if storage_state else None,
        )
        try:
            _do_capture_context(ctx, url, out, width, height, wait_ms, full_page)
        finally:
            ctx.close()
        return out.resolve()

    with sync_playwright() as pw:
        br = pw.chromium.launch(
            headless=not headed,
            args=CHROMIUM_LAUNCH_ARGS,
        )
        try:
            ctx = br.new_context(
                viewport={"width": width, "height": height},
                storage_state=str(storage_state) if storage_state else None,
            )
            try:
                _do_capture_context(
                    ctx, url, out, width, height, wait_ms, full_page
                )
            finally:
                ctx.close()
        finally:
            br.close()

    return out.resolve()


def _tv_dismiss_overlays(page: Page) -> None:
    """Cookie / banery (PL/EN) — best-effort; bez tego część UI zasłania wykres."""
    for name in (
        "Akceptuję",
        "Akceptuj wszystkie",
        "Akceptuj",
        "Accept all",
        "Accept",
    ):
        try:
            page.get_by_role("button", name=name).click(timeout=2000)
            time.sleep(0.4)
            break
        except Exception:
            continue


def _do_capture_context(
    context: BrowserContext,
    url: str,
    out: Path,
    width: int,
    height: int,
    wait_ms: int,
    full_page: bool,
) -> None:
    # Viewport ustawia się przy browser.new_context(...); new_page() nie przyjmuje viewport.
    page = context.new_page()
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=120_000)
        _tv_dismiss_overlays(page)
        time.sleep(wait_ms / 1000.0)
        page.screenshot(path=str(out), full_page=full_page)
    finally:
        page.close()


def main() -> int:
    p = argparse.ArgumentParser(description="Screenshot jednej strony (viewport).")
    p.add_argument("--url", required=True, help="Pełny URL (np. link do chartu TV).")
    p.add_argument(
        "--out",
        default="",
        help="Plik PNG wyjściowy (domyślnie docs/tv_playwright_capture.png w rootcie repo).",
    )
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument(
        "--wait-ms",
        type=int,
        default=8000,
        help="Czekanie po domcontentloaded (ms) — czas na namalowanie świec.",
    )
    p.add_argument(
        "--headed",
        action="store_true",
        help="Okno widoczne (logowanie, CAPTCHA, debug).",
    )
    p.add_argument(
        "--full-page",
        action="store_true",
        help="Pełna strona zamiast samego viewportu.",
    )
    p.add_argument(
        "--storage-state",
        default="",
        help="Plik JSON z Playwright (save_tv_storage_state.py) — sesja zalogowanego TV.",
    )
    args = p.parse_args()

    out = Path(args.out) if args.out else _repo_root() / "docs" / "tv_playwright_capture.png"
    ss = Path(args.storage_state) if args.storage_state else None
    capture_screenshot(
        args.url,
        out,
        width=args.width,
        height=args.height,
        wait_ms=args.wait_ms,
        headed=args.headed,
        full_page=args.full_page,
        browser=None,
        browser_context=None,
        storage_state=ss,
    )
    print(str(out.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
