import sharp from "sharp";
import { Deck, SLIDE_H, SLIDE_W, Slide, uid } from "./types";
import { normalizeTheme } from "./normalize";
import { saveAsset } from "./assets";
import { chatJSON, editImage, pickTextModel, pickTransparentImageModels } from "./openai";
import { DEFAULT_ZONE, applyContrast, sanitizeZone, typesetZone } from "./image2Pipeline";

// PDF取り込み: 画像だけのPDF資料(NotebookLM等の出力)を編集可能なデッキに分解する。
//  1. pdfjs + @napi-rs/canvas で各ページを1280x720に近いビットマップへ
//  2. ビジョン: テキスト(役割付き・一字一句)と、テキストが占める領域(ゾーン)を抽出
//  3. gpt-image edits: 文字だけを消した背景画像を作る
//  4. 抽出テキストを既存の組版エンジンでゾーンに組み直す(色は背景輝度から実測)
// 結果: 背景=画像、テキスト=編集可能な要素、という image2 と同じ2層構成になる。

const MAX_PAGES = 12;

const THEME_SYSTEM = `スライド資料の1ページ目の画像から、デッキ全体のテーマをJSONで返します。

出力(JSONのみ): {
  "title": "資料タイトル(内容から)",
  "colors": { "brand": "#hex", "brandDark": "#hex", "brandSoft": "#hex", "accent": "#hex", "bg": "#hex", "surface": "#hex", "ink": "#hex", "muted": "#hex", "line": "#hex" },
  "headingFont": "'Noto Sans JP', sans-serif" など(候補: 'Noto Sans JP'/'Noto Serif JP'/'Zen Kaku Gothic New'/'M PLUS Rounded 1c'/'Shippori Mincho'),
  "bodyFont": 同上
}
画像の実際の配色から9トークンを抽出し、雰囲気の近いフォントを選ぶ。`;

const EXTRACT_SYSTEM = `あなたはスライドの構造化エンジンです。スライド画像(1280x720)から、テキスト内容とレイアウトをJSONで返します。

出力(JSONのみ): {
  "name": "ページ名(内容を短く)",
  "texts": [ { "role": "kicker|title|subtitle|body|stat|label", "text": "画像内の実際の文言" } ],
  "zone": { "x": 0-1280, "y": 0-720, "w": px, "h": px }
}

- texts: 画像に書かれている全テキストを、誤字なく一字一句正確に。役割は見た目(大きさ・位置)から判断
- 箇条書きは1項目=1テキスト(role: body)
- zone: テキスト一式が置かれている領域(再配置先にも使う)
- テキストが無いページは "texts": []`;

const CLEAN_PROMPT =
  "Remove ALL text, letters, words, numbers and typography completely from this slide. " +
  "Keep the background design, colors, shapes, photos and illustrations exactly as they are, " +
  "filling the areas where text was removed seamlessly with the surrounding background.";

// pdfjsでPDFの各ページを1280px幅のPNGにラスタライズする
async function rasterize(pdf: Buffer): Promise<Buffer[]> {
  const canvasMod = await import("@napi-rs/canvas");
  globalThis.DOMMatrix ??= canvasMod.DOMMatrix as unknown as typeof globalThis.DOMMatrix;
  globalThis.Path2D ??= canvasMod.Path2D as unknown as typeof globalThis.Path2D;
  globalThis.ImageData ??= canvasMod.ImageData as unknown as typeof globalThis.ImageData;
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const doc = await pdfjs.getDocument({
    data: new Uint8Array(pdf),
    useSystemFonts: false,
    disableFontFace: true,
  }).promise;
  const pages: Buffer[] = [];
  for (let i = 1; i <= Math.min(doc.numPages, MAX_PAGES); i++) {
    const page = await doc.getPage(i);
    const base = page.getViewport({ scale: 1 });
    const vp = page.getViewport({ scale: SLIDE_W / base.width });
    const canvas = canvasMod.createCanvas(Math.round(vp.width), Math.round(vp.height));
    const ctx = canvas.getContext("2d");
    await page.render({
      canvas: canvas as unknown as HTMLCanvasElement,
      canvasContext: ctx as unknown as CanvasRenderingContext2D,
      viewport: vp,
    }).promise;
    // 16:9でないページは白地の1280x720に収める
    const png = await sharp(canvas.toBuffer("image/png"))
      .resize(SLIDE_W, SLIDE_H, { fit: "contain", background: "#FFFFFF" })
      .png()
      .toBuffer();
    pages.push(png);
  }
  return pages;
}

async function asyncPool<T, R>(
  limit: number,
  items: T[],
  fn: (item: T, i: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

function imageContent(jpeg: Buffer) {
  return {
    type: "image_url" as const,
    image_url: { url: `data:image/jpeg;base64,${jpeg.toString("base64")}`, detail: "high" as const },
  };
}

export async function importPdfDeck(pdf: Buffer): Promise<Deck> {
  const pages = await rasterize(pdf);
  if (pages.length === 0) throw new Error("PDFにページがありません");
  const textModel = await pickTextModel();
  const editModels = await pickTransparentImageModels(); // editsはgpt-image-1系が安定
  const editModel = editModels[0];
  if (!editModel) throw new Error("画像編集モデルが使えません");

  // テーマは1ページ目から抽出
  const firstSmall = await sharp(pages[0]).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
  const themeRaw = await chatJSON<{ title?: string; colors?: Record<string, string>; headingFont?: string; bodyFont?: string }>(
    textModel,
    THEME_SYSTEM,
    [imageContent(firstSmall), { type: "text", text: "この資料のテーマを抽出してください。" }],
    4000,
  );
  const theme = normalizeTheme(themeRaw);

  const slides = await asyncPool(2, pages, async (png, i): Promise<Slide> => {
    try {
      const small = await sharp(png).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
      const ext = await chatJSON<{
        name?: string;
        texts?: { role?: string; text?: string }[];
        zone?: unknown;
      }>(
        textModel,
        EXTRACT_SYSTEM,
        [imageContent(small), { type: "text", text: "このスライドを構造化してください(座標は1280x720系)。" }],
        8000,
      );
      const texts = (ext.texts ?? [])
        .filter((t) => typeof t?.text === "string" && t.text.trim())
        .slice(0, 8)
        .map((t) => ({ role: t.role || "body", text: t.text! }));

      // 文字を消した背景を作る(editsの3:2出力を実測済みのfit:fillで戻す)
      const cleanRaw = await editImage(editModel, png, CLEAN_PROMPT, {});
      const clean = await sharp(cleanRaw).resize(SLIDE_W, SLIDE_H, { fit: "fill" }).png().toBuffer();
      const url = await saveAsset(`bg-${uid()}`, clean);

      const zone = sanitizeZone(ext.zone) ?? DEFAULT_ZONE;
      const elements =
        texts.length > 0 ? await applyContrast(typesetZone(texts, zone), texts, clean, theme) : [];
      return {
        id: uid(),
        name: ext.name || `ページ ${i + 1}`,
        background: { color: "token:bg", preset: "none", image: url },
        elements,
      };
    } catch (e) {
      console.error(`pdf page ${i + 1} import failed:`, e);
      // 分解に失敗したページは元のビットマップをそのまま背景にする(内容は失わない)
      const url = await saveAsset(`bg-${uid()}`, png);
      return {
        id: uid(),
        name: `ページ ${i + 1}`,
        background: { color: "token:bg", preset: "none", image: url },
        elements: [],
      };
    }
  });

  return { id: uid(), title: themeRaw.title || "インポートした資料", theme, slides };
}
