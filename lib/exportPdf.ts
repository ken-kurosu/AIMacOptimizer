import { existsSync } from "fs";
import { chromium } from "playwright-core";
import { Deck } from "./types";

// サーバーサイドPDF書き出し。インストール済みのChrome/Chromiumを自動検出し、
// ヘッドレスで印刷ビューを開いて page.pdf() する。リンクアノテーションも保持される。
// ブラウザのダウンロードは行わない(見つからなければ呼び出し側が印刷ビューへフォールバック)。

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  // macOS
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  // Linux
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
  // Windows
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
];

export function findChrome(): string | null {
  for (const p of CHROME_CANDIDATES) {
    if (p && existsSync(/* turbopackIgnore: true */ p)) return p;
  }
  return null;
}

export async function renderDeckPdf(origin: string, deckId: string, deck: Deck): Promise<Buffer> {
  const executablePath = findChrome();
  if (!executablePath) {
    throw new Error(
      "Chrome/Chromiumが見つかりません。CHROME_PATH 環境変数で実行ファイルを指定するか、印刷ビューから書き出してください",
    );
  }
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    await page.goto(`${origin}/print?deck=${deckId}`, { waitUntil: "networkidle" });
    // 全スライドの描画とWebフォント・背景画像の読み込みを待つ
    await page.waitForFunction(
      (n) => document.querySelectorAll(".print-slide").length >= n,
      deck.slides.length,
      { timeout: 30000 },
    );
    await page.evaluate(async () => {
      await document.fonts.ready;
      const imgs = Array.from(document.images);
      await Promise.all(
        imgs.map((img) =>
          img.complete ? null : new Promise((r) => img.addEventListener("load", r, { once: true })),
        ),
      );
    });
    await page.waitForTimeout(300);
    const pdf = await page.pdf({
      preferCSSPageSize: true, // 印刷ビューの @page 13.333in x 7.5in を使う
      printBackground: true,
    });
    return Buffer.from(pdf);
  } finally {
    await browser.close();
  }
}
