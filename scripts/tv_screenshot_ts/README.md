# Zrzuty wykresu — wersja TypeScript (Playwright)

**Opcjonalna** alternatywa dla `scripts/tv_screenshot/` (Python). Nie musisz z tego korzystać, jeśli wystarczy `.venv` + `screenshot_tv.py`.

## Wymagania

- **Node.js LTS** (npm w PATH): https://nodejs.org/

## Instalacja (raz)

```powershell
cd ...\DailySessionLogger_v2\scripts\tv_screenshot_ts
npm install
npx playwright install chromium
```

## Uruchomienie

Z tego samego folderu `tv_screenshot_ts`:

```powershell
npm run screenshot -- --url "https://www.tradingview.com/chart/?symbol=..."
```

Domyślny plik wyjściowy: **`docs/tv_playwright_capture_ts.png`** (w rootcie repo, dwa poziomy wyżej).

Flagi (jak w Pythonie): `--out`, `--width`, `--height`, `--wait-ms`, `--headed`, `--full-page`.

## Uwagi

- Binaria Chromium Playwright lądują w `%LOCALAPPDATA%\ms-playwright\` (współdzielone z instalacją z Pythona, jeśli ta sama wersja silnika).
- `node_modules/` jest w `.gitignore` — każdy klon robi `npm install` lokalnie.
