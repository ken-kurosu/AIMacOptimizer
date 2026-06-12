import { promises as fs } from "fs";
import path from "path";
import sharp from "sharp";
import { chromium } from "playwright-core";
import { Deck, Slide, Theme, uid } from "./types";
import { findChrome } from "./exportPdf";
import { readAsset } from "./assets";
import { applyContrast, sanitizeZone, typesetZone } from "./image2Pipeline";
import { chatJSON } from "./openai";

// 批評ループ: 生成済みデッキを実際にレンダリングしたスクリーンショットを
// ビジョンモデルに検査させ、問題のあるページはテキストゾーンを置き直して
// 決定的に組み直す。レンダリングにはPDF書き出しと同じヘッドレスChromeを
// 使うため、Chromeが見つからない環境では静かにスキップする(生成は成功扱い)。

const CRITIC_SYSTEM = `あなたはプレゼンテーションの品質検査員です。完成スライドのスクリーンショット(1280x720)を見て、レイアウト品質の問題をJSONで返します。

出力(JSONのみ): { "ok": boolean, "issues": ["問題の簡潔な説明"], "zone": { "x": 0-1280, "y": 0-720, "w": px, "h": px } }

必ず ok:false にする重大な問題:
- テキスト同士が重なって読めない・行が衝突している
- テキストがスライドの外にはみ出している
- テキストが背景の濃い絵柄・図形の上にあり、コントラスト不足で読めない

判定:
- 上記がなく、配置の好みの差しかないなら { "ok": true } だけを返す
- 重大な問題があるときは ok:false とし、テキスト一式を置き直すべき領域を zone で指定する(背景の空いている場所。端から64px以上の余白。テキスト全量が入る大きさ)`;

interface Critique {
  ok?: boolean;
  issues?: string[];
  zone?: unknown;
}

// 全スライドを実レンダリングしてスクリーンショットを撮る(1回のブラウザ起動で済ませる)
async function screenshotDeck(origin: string, deck: Deck): Promise<Buffer[] | null> {
  const executablePath = findChrome();
  if (!executablePath) return null;

  const id = uid();
  const file = path.join(process.cwd(), ".assets", `export-${id}.json`);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, JSON.stringify(deck));
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1320, height: 780 } });
    await page.goto(`${origin}/print?deck=${id}`, { waitUntil: "networkidle" });
    await page.waitForFunction(
      (n) => document.querySelectorAll(".print-slide").length >= n,
      deck.slides.length,
      { timeout: 30000 },
    );
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all(
        Array.from(document.images).map((img) =>
          img.complete ? null : new Promise((r) => img.addEventListener("load", r, { once: true })),
        ),
      );
    });
    const nodes = await page.locator(".print-slide").all();
    const shots: Buffer[] = [];
    for (const node of nodes) {
      const png = await node.screenshot({ type: "png" });
      // トークン節約のため縮小JPEGで渡す(判定座標は1280x720系で返させる)
      shots.push(await sharp(png).resize(800, 450).jpeg({ quality: 80 }).toBuffer());
    }
    return shots;
  } finally {
    await browser.close();
    await fs.unlink(file).catch(() => {});
  }
}

// 問題ありと判定されたページを、新しいゾーンで組み直す(画像は再生成しない)
async function refitSlide(slide: Slide, zone: NonNullable<ReturnType<typeof sanitizeZone>>, theme: Theme): Promise<boolean> {
  const assetId = slide.background.image?.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
  if (!assetId) return false;
  const bg = await readAsset(assetId);
  if (!bg) return false;
  const texts = slide.elements
    .filter((e) => e.type === "text")
    .map((e) => ({ role: e.name ?? "body", text: e.text }));
  if (texts.length === 0) return false;
  slide.elements = await applyContrast(typesetZone(texts, zone), texts, bg, theme);
  return true;
}

export async function critiqueAndFixDeck(
  origin: string,
  deck: Deck,
  textModel: string,
): Promise<{ checked: number; fixed: number }> {
  const shots = await screenshotDeck(origin, deck);
  if (!shots) return { checked: 0, fixed: 0 };

  let fixed = 0;
  await Promise.all(
    deck.slides.map(async (slide, i) => {
      const shot = shots[i];
      if (!shot || !slide.background.image) return;
      try {
        const result = await chatJSON<Critique>(
          textModel,
          CRITIC_SYSTEM,
          [
            {
              type: "image_url",
              image_url: { url: `data:image/jpeg;base64,${shot.toString("base64")}`, detail: "high" },
            },
            { type: "text", text: "このスライドを検査してください(座標は1280x720系で回答)。" },
          ],
          4000,
        );
        const zone = sanitizeZone(result.zone);
        console.log(
          `critique: slide ${i + 1} ok=${result.ok}` +
            (result.issues?.length ? ` issues=${result.issues.join(" / ")}` : ""),
        );
        if (result.ok === false && zone) {
          if (await refitSlide(slide, zone, deck.theme)) {
            fixed++;
            console.log(`critique: slide ${i + 1} refit to zone ${JSON.stringify(zone)}`);
          }
        }
      } catch (e) {
        console.warn(`critique: slide ${i + 1} skipped:`, e instanceof Error ? e.message : e);
      }
    }),
  );
  return { checked: shots.length, fixed };
}
