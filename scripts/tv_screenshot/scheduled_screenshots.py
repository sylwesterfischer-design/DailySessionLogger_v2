"""
Cykliczne zrzuty wykresu TradingView (Playwright, jedna instancja Chromium).

Konfiguracja: capture_schedule.json obok tego pliku (wzór: capture_schedule.example.json).

Uruchomienie z rootu repo:
  .\\.venv\\Scripts\\python scripts\\tv_screenshot\\scheduled_screenshots.py

Zatrzymanie: Ctrl+C. Działa w tle — możesz użyć Start-Process w PowerShell.

Logi (wazne przy pythonw / Harmonogramie — brak konsoli): domyslnie docs/tv_scheduled/tv_capture.log
"""
from __future__ import annotations

import json
import logging
import math
import os
import sys
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

# Czas w nazwie PNG (nie w logach — logi dalej UTC).
_FILENAME_TS_TZ = ZoneInfo("Europe/Warsaw")

from playwright.sync_api import sync_playwright

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from screenshot_tv import CHROMIUM_LAUNCH_ARGS, capture_screenshot

_LOG = logging.getLogger("tv_scheduled")


def _utc_formatter() -> logging.Formatter:
    fmt = logging.Formatter(
        "%(asctime)sZ %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    fmt.converter = time.gmtime
    return fmt


def _append_bootstrap(log_file: Path, msg: str) -> None:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with log_file.open("a", encoding="utf-8") as f:
        f.write(f"{ts} {msg}\n")


def _setup_file_logging(log_file: Path) -> None:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    root.handlers.clear()
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(_utc_formatter())
    root.addHandler(fh)
    if sys.stderr and getattr(sys.stderr, "isatty", lambda: False)():
        sh = logging.StreamHandler(sys.stderr)
        sh.setLevel(logging.INFO)
        sh.setFormatter(_utc_formatter())
        root.addHandler(sh)


def _config_path() -> Path:
    return Path(__file__).resolve().parent / "capture_schedule.json"


def _load_config() -> dict:
    p = _config_path()
    if not p.is_file():
        print(
            f"Brak {p.name}. Skopiuj capture_schedule.example.json → capture_schedule.json i edytuj URL.",
            file=sys.stderr,
        )
        sys.exit(2)
    with p.open(encoding="utf-8") as f:
        return json.load(f)


def _strip_comment_keys(obj: dict) -> dict:
    return {k: v for k, v in obj.items() if not k.startswith("_")}


def _next_minute_boundary(ts: float) -> float:
    return float(math.floor(ts / 60.0) + 1) * 60.0


def _first_run_ts(period_seconds: int, align: str, now: float, stagger_s: float) -> float:
    if align == "minute":
        return _next_minute_boundary(now) + stagger_s
    return now + 2.0 + stagger_s


def _next_after_capture(
    period_seconds: int, align: str, after_ts: float
) -> float:
    if align == "minute":
        return _next_minute_boundary(after_ts)
    return after_ts + float(period_seconds)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    default_log = repo_root / "docs" / "tv_scheduled" / "tv_capture.log"

    cfg_path = _config_path()
    if not cfg_path.is_file():
        _append_bootstrap(
            default_log,
            f"ERROR brak {cfg_path.name} — skopiuj capture_schedule.example.json",
        )
        return 2

    try:
        raw = _load_config()
    except Exception as e:
        _append_bootstrap(default_log, f"ERROR odczyt JSON: {e!r}\n{traceback.format_exc()}")
        return 2

    cfg = _strip_comment_keys(raw)
    log_rel = str(cfg.get("log_file", "docs/tv_scheduled/tv_capture.log"))
    log_file = Path(log_rel) if Path(log_rel).is_absolute() else repo_root / log_rel
    _setup_file_logging(log_file)

    _LOG.info(
        "START pid=%s exe=%s cwd=%s script=%s",
        os.getpid(),
        sys.executable,
        os.getcwd(),
        Path(__file__).resolve(),
    )

    try:
        template = cfg["chart_url_template"]
        wait_ms = int(cfg.get("wait_ms", 8000))
        name_suffix = str(cfg.get("filename_suffix", "chart")).strip()
        vp = cfg.get("viewport", {})
        w, h = int(vp.get("width", 1920)), int(vp.get("height", 1080))
        out_rel = cfg.get("output_dir", "docs/tv_scheduled")
        headed = bool(cfg.get("headed", False))
        headless = not headed
        out_dir = repo_root / out_rel
        out_dir.mkdir(parents=True, exist_ok=True)

        _LOG.info("repo_root=%s", repo_root)
        _LOG.info("output_dir=%s (PNG)", out_dir.resolve())
        _LOG.info("log_file=%s", log_file.resolve())
        _LOG.info("headed=%s headless=%s", headed, headless)

        ss_raw = cfg.get("storage_state", "")
        storage_path: str | None = None
        if ss_raw:
            p = Path(ss_raw)
            storage_path = str(p if p.is_absolute() else repo_root / p)
            if not Path(storage_path).is_file():
                _LOG.warning(
                    "brak storage_state=%s — zrzuty bez zalogowanej sesji TV",
                    storage_path,
                )
                storage_path = None
        else:
            _LOG.info("storage_state=(pusty) — brak pliku sesji TV")

        jobs = cfg["jobs"]
        _LOG.info("jobs=%d: %s", len(jobs), [j.get("label") for j in jobs])

        models_log_cfg = cfg.get("models_log")
        models_enabled = (
            isinstance(models_log_cfg, dict) and bool(models_log_cfg.get("enabled"))
        )
        if models_enabled:
            _LOG.info("models_log wlaczony excel_path=%s", models_log_cfg.get("excel_path"))

        now = time.time()
        next_run: list[float] = []
        for idx, j in enumerate(jobs):
            align = j.get("align", "interval")
            psec = int(j["period_seconds"])
            stagger = float(idx) * 3.0
            next_run.append(_first_run_ts(psec, align, now, stagger))

        _LOG.info("harmonogram startuje; Ctrl+C=stop (konsola). Nastepne zrzuty wg next_run.")

        with sync_playwright() as pw:
            _LOG.info(
                "Playwright: uruchamiam Chromium headless=%s args=%s",
                headless,
                CHROMIUM_LAUNCH_ARGS,
            )
            browser = pw.chromium.launch(
                headless=headless,
                args=CHROMIUM_LAUNCH_ARGS,
            )
            ctx = browser.new_context(
                viewport={"width": w, "height": h},
                storage_state=storage_path,
            )
            try:
                while True:
                    now = time.time()
                    due = [i for i, t in enumerate(next_run) if t <= now]
                    if not due:
                        nxt = min(next_run)
                        sleep_for = min(1.0, max(0.05, nxt - now))
                        time.sleep(sleep_for)
                        continue

                    for i in due:
                        job = jobs[i]
                        label = job["label"]
                        iv = str(job["tv_interval"])
                        url = template.format(tv_interval=iv)
                        ts_name = datetime.now(_FILENAME_TS_TZ).strftime(
                            "%Y%m%d_%H%M%S"
                        )
                        if name_suffix:
                            fname = f"{label}_{ts_name}_{name_suffix}.png"
                        else:
                            fname = f"{label}_{ts_name}.png"
                        out_path = out_dir / fname

                        try:
                            _LOG.info("CAPTURE start tf=%s tv_interval=%s url=%s", label, iv, url)
                            capture_screenshot(
                                url=url,
                                out=out_path,
                                width=w,
                                height=h,
                                wait_ms=wait_ms,
                                headed=False,
                                full_page=False,
                                browser_context=ctx,
                            )
                            sz = out_path.stat().st_size if out_path.is_file() else 0
                            _LOG.info(
                                "CAPTURE ok tf=%s file=%s bytes=%s",
                                label,
                                out_path.resolve(),
                                sz,
                            )
                            if models_enabled:
                                try:
                                    from models_excel_logger import (
                                        log_capture_to_excel,
                                    )

                                    ts_pl = (
                                        datetime.now(_FILENAME_TS_TZ)
                                        .replace(microsecond=0)
                                        .isoformat()
                                    )
                                    log_capture_to_excel(
                                        repo_root=repo_root,
                                        models_cfg=models_log_cfg,
                                        tf_label=label,
                                        png_path=out_path,
                                        timestamp_pl_iso=ts_pl,
                                        parent_log=_LOG,
                                    )
                                except Exception:
                                    _LOG.exception(
                                        "models_log FAIL tf=%s file=%s",
                                        label,
                                        out_path,
                                    )
                        except Exception:
                            _LOG.exception("CAPTURE FAIL tf=%s url=%s", label, url)

                        next_run[i] = _next_after_capture(
                            int(job["period_seconds"]),
                            job.get("align", "interval"),
                            time.time(),
                        )
            finally:
                ctx.close()
                browser.close()
                _LOG.info("Chromium zamkniety")

    except Exception:
        _LOG.exception("FATAL — koniec procesu")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
