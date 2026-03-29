/**
 * Odpowiednik `scripts/tv_screenshot/screenshot_tv.py` — Playwright + Chromium (TypeScript).
 * Nie loguje na TV; pełny URL chartu; `--headed` do ręcznego logowania.
 *
 * Wymaga: Node.js + `npm install` + `npx playwright install chromium` w tym folderze.
 */
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = dirname(fileURLToPath(import.meta.url));

function repoRoot(): string {
  return resolve(__dirname, "..", "..");
}

function parseArgs(argv: string[]): {
  url: string;
  out: string;
  width: number;
  height: number;
  waitMs: number;
  headed: boolean;
  fullPage: boolean;
} {
  let url = "";
  let out = "";
  let width = 1920;
  let height = 1080;
  let waitMs = 8000;
  let headed = false;
  let fullPage = false;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--url" && argv[i + 1]) {
      url = argv[++i];
    } else if (a === "--out" && argv[i + 1]) {
      out = argv[++i];
    } else if (a === "--width" && argv[i + 1]) {
      width = Number(argv[++i]);
    } else if (a === "--height" && argv[i + 1]) {
      height = Number(argv[++i]);
    } else if (a === "--wait-ms" && argv[i + 1]) {
      waitMs = Number(argv[++i]);
    } else if (a === "--headed") {
      headed = true;
    } else if (a === "--full-page") {
      fullPage = true;
    }
  }

  if (!url) {
    console.error("Brak --url. Przykład: npm run screenshot -- --url \"https://...\"");
    process.exit(1);
  }

  const defaultOut = join(repoRoot(), "docs", "tv_playwright_capture_ts.png");
  return { url, out: out || defaultOut, width, height, waitMs, headed, fullPage };
}

async function main(): Promise<void> {
  const { url, out, width, height, waitMs, headed, fullPage } = parseArgs(
    process.argv.slice(2),
  );

  await mkdir(dirname(out), { recursive: true });

  const browser = await chromium.launch({ headless: !headed });
  const page = await browser.newPage({ viewport: { width, height } });
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120_000 });
  await new Promise((r) => setTimeout(r, waitMs));
  const buf = await page.screenshot({ fullPage });
  await browser.close();

  await writeFile(out, buf);
  console.log(resolve(out));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
