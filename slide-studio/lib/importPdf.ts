import sharp from "sharp";
import { Deck, SLIDE_H, SLIDE_W, Slide, TextEl, clamp, uid } from "./types";
import { normalizeTheme } from "./normalize";
import { saveAsset } from "./assets";
import { chatJSON, editImage, openaiAvailable, pickTextModel, pickTransparentImageModels } from "./openai";
import { DEFAULT_ZONE, applyContrast, sanitizeZone, typesetZone } from "./image2Pipeline";

// PDF取り込み: PDF資料を編集可能なデッキに分解する。ページごとに自動で2経路に分岐:
//  (A) テキストレイヤーのあるPDF(PowerPoint/Keynote/Googleスライド書き出し等)
//      → pdfjsで文字・座標・サイズを正確に取得し、その場に編集可能テキストを配置。
//        背景はテキスト領域を周囲色で塗り潰して除去(gpt-image不要=無料・高速)。
//        元の位置・サイズ・フォント感を保ったまま、文字だけ打ち直せる。
//  (B) 画像だけのPDF(NotebookLM等のスクショ資料)
//      → ビジョンでOCR + gpt-imageで文字除去 → 組版エンジンで再配置(従来方式)。
// どちらも「背景=画像、テキスト=編集可能要素」という image2 と同じ2層構成になる。

const MAX_PAGES = 12;
// このページを「テキストPDF」とみなす最小文字数(これ未満は画像PDF経路へ)
const VECTOR_MIN_CHARS = 8;

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

// ---- pdfjsの座標を1280x720デバイス座標へ写すための情報 -----------------
interface PdfRun {
  text: string;
  x: number; // 左上(1280x720系)
  y: number;
  w: number;
  h: number; // ≒ fontSize
  fontSize: number;
  bold: boolean;
  serif: boolean;
  eol: boolean; // 行末
}

interface RasterPage {
  png: Buffer; // 1280x720
  runs: PdfRun[]; // テキストレイヤー(無ければ空)
}

// pdfjsで各ページを1280x720にラスタライズし、テキストレイヤーも抽出する
async function rasterizePages(pdf: Buffer): Promise<RasterPage[]> {
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

  const out: RasterPage[] = [];
  for (let i = 1; i <= Math.min(doc.numPages, MAX_PAGES); i++) {
    const page = await doc.getPage(i);
    const base = page.getViewport({ scale: 1 });
    const scale = SLIDE_W / base.width;
    const vp = page.getViewport({ scale });
    const canvas = canvasMod.createCanvas(Math.round(vp.width), Math.round(vp.height));
    const ctx = canvas.getContext("2d");
    await page.render({
      canvas: canvas as unknown as HTMLCanvasElement,
      canvasContext: ctx as unknown as CanvasRenderingContext2D,
      viewport: vp,
    }).promise;

    // 16:9でないページは白地の1280x720に contain で収める。
    // テキスト座標にも同じ変換(scale2 + 余白オフセット)を適用する必要がある
    const devW = vp.width;
    const devH = vp.height;
    const scale2 = Math.min(SLIDE_W / devW, SLIDE_H / devH);
    const offX = (SLIDE_W - devW * scale2) / 2;
    const offY = (SLIDE_H - devH * scale2) / 2;

    const png = await sharp(canvas.toBuffer("image/png"))
      .resize(SLIDE_W, SLIDE_H, { fit: "contain", background: "#FFFFFF" })
      .png()
      .toBuffer();

    let runs: PdfRun[] = [];
    try {
      const tc = await page.getTextContent();
      runs = mapTextRuns(pdfjs, tc.items, vp.transform, scale, scale2, offX, offY);
    } catch (e) {
      console.warn(`pdf page ${i}: getTextContent failed:`, e instanceof Error ? e.message : e);
    }
    out.push({ png, runs });
  }
  return out;
}

interface PdfJsItem {
  str?: string;
  width?: number;
  height?: number;
  transform?: number[];
  fontName?: string;
  hasEOL?: boolean;
}

interface PdfJsLike {
  Util: { transform(a: number[], b: number[]): number[] };
}

function mapTextRuns(
  pdfjs: PdfJsLike,
  items: unknown[],
  vpTransform: number[],
  scale: number,
  scale2: number,
  offX: number,
  offY: number,
): PdfRun[] {
  const runs: PdfRun[] = [];
  for (const raw of items) {
    const it = raw as PdfJsItem;
    const str = typeof it.str === "string" ? it.str : "";
    if (!str.trim() && !it.hasEOL) continue;
    const tr = it.transform;
    if (!tr || tr.length < 6) continue;
    // 回転テキストは扱わない(横書きのみ。bが大きい=傾き)
    if (Math.abs(tr[1]) > Math.abs(tr[0]) * 0.4) continue;
    const m = pdfjs.Util.transform(vpTransform, tr); // device座標
    const fontDev = Math.hypot(m[2], m[3]); // フォント高(device px)
    if (!Number.isFinite(fontDev) || fontDev <= 0) continue;
    const wDev = (it.width ?? 0) * scale; // 文字列幅(device px)
    const baseX = m[4];
    const baseY = m[5]; // ベースライン(device, 上原点)
    const topDev = baseY - fontDev; // emの上端を概算

    const x = baseX * scale2 + offX;
    const y = topDev * scale2 + offY;
    const w = wDev * scale2;
    const fontSize = fontDev * scale2;
    const fn = it.fontName ?? "";
    runs.push({
      text: str,
      x,
      y,
      w: w > 1 ? w : str.length * fontSize * 0.5,
      h: fontSize,
      fontSize,
      bold: /bold|black|heavy|semibold|w[6-9]/i.test(fn),
      serif: /serif|mincho|min[cs]ho|times|georgia|roman/i.test(fn),
      eol: it.hasEOL === true,
    });
  }
  return runs;
}

// 連続するrunを「行」にまとめる。同じベースライン(yが近い)で隣接する断片を連結する。
// 行ごとに1つの編集可能テキスト要素にすると、編集しやすく要素数も抑えられる。
function groupLines(runs: PdfRun[]): PdfRun[] {
  const sorted = [...runs].sort((a, b) => a.y - b.y || a.x - b.x);
  const lines: PdfRun[] = [];
  let cur: PdfRun | null = null;
  for (const r of sorted) {
    if (!r.text) {
      if (cur && r.eol) cur = null; // 空のEOLは行の区切り
      continue;
    }
    const sameLine =
      cur &&
      Math.abs(r.y - cur.y) < cur.fontSize * 0.6 &&
      r.x >= cur.x - 4 &&
      r.x - (cur.x + cur.w) < cur.fontSize * 1.2;
    if (cur && sameLine) {
      // 単語間に隙間があればスペースを補う
      const gap = r.x - (cur.x + cur.w);
      if (gap > cur.fontSize * 0.25 && !/\s$/.test(cur.text)) cur.text += " ";
      cur.text += r.text;
      cur.w = r.x + r.w - cur.x;
      cur.fontSize = Math.max(cur.fontSize, r.fontSize);
      cur.h = cur.fontSize;
      cur.bold = cur.bold || r.bold;
      if (r.eol) cur = null;
    } else {
      cur = { ...r };
      lines.push(cur);
      if (r.eol) cur = null;
    }
  }
  return lines.filter((l) => l.text.trim().length > 0);
}

// ---- 色のサンプリング(元ラスタから) ------------------------------------
function rgbAt(raw: Buffer, x: number, y: number): [number, number, number] {
  const xi = clamp(Math.round(x), 0, SLIDE_W - 1);
  const yi = clamp(Math.round(y), 0, SLIDE_H - 1);
  const i = (yi * SLIDE_W + xi) * 3;
  return [raw[i], raw[i + 1], raw[i + 2]];
}

function toHex(r: number, g: number, b: number): string {
  return "#" + [r, g, b].map((v) => clamp(Math.round(v), 0, 255).toString(16).padStart(2, "0")).join("");
}

// bboxの外周リングの中央値 ≒ 背景色
function ringColor(raw: Buffer, r: PdfRun): [number, number, number] {
  const samples: [number, number, number][] = [];
  const x0 = r.x - 3, x1 = r.x + r.w + 3, y0 = r.y - 3, y1 = r.y + r.h + 3;
  for (let t = 0; t <= 1.0001; t += 0.1) {
    samples.push(rgbAt(raw, x0 + (x1 - x0) * t, y0));
    samples.push(rgbAt(raw, x0 + (x1 - x0) * t, y1));
    samples.push(rgbAt(raw, x0, y0 + (y1 - y0) * t));
    samples.push(rgbAt(raw, x1, y0 + (y1 - y0) * t));
  }
  return medianColor(samples);
}

function medianColor(s: [number, number, number][]): [number, number, number] {
  if (s.length === 0) return [255, 255, 255];
  const med = (k: 0 | 1 | 2) => {
    const v = s.map((c) => c[k]).sort((a, b) => a - b);
    return v[v.length >> 1];
  };
  return [med(0), med(1), med(2)];
}

function dist2(a: [number, number, number], b: [number, number, number]): number {
  return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
}

// テキスト色 = bbox内で背景色から最も離れた色の平均(濃淡どちらの文字にも対応)
function textColor(raw: Buffer, r: PdfRun, bg: [number, number, number], inkFallback: string): string {
  let sum = [0, 0, 0];
  let n = 0;
  const x0 = Math.round(r.x), x1 = Math.round(r.x + r.w), y0 = Math.round(r.y), y1 = Math.round(r.y + r.h);
  const stepX = Math.max(1, Math.round((x1 - x0) / 40));
  const stepY = Math.max(1, Math.round((y1 - y0) / 14));
  for (let y = y0; y < y1; y += stepY) {
    for (let x = x0; x < x1; x += stepX) {
      const c = rgbAt(raw, x, y);
      if (dist2(c, bg) > 2400) {
        sum = [sum[0] + c[0], sum[1] + c[1], sum[2] + c[2]];
        n++;
      }
    }
  }
  if (n < 3) return inkFallback;
  return toHex(sum[0] / n, sum[1] / n, sum[2] / n);
}

// テキスト領域を周囲色で塗り潰して背景から文字を消す(決定的・無料)
async function paintOverText(png: Buffer, lines: PdfRun[], raw: Buffer): Promise<Buffer> {
  const out = Buffer.from(raw); // RGB
  for (const r of lines) {
    const [br, bg, bb] = ringColor(raw, r);
    const x0 = clamp(Math.floor(r.x - 2), 0, SLIDE_W);
    const x1 = clamp(Math.ceil(r.x + r.w + 2), 0, SLIDE_W);
    const y0 = clamp(Math.floor(r.y - 2), 0, SLIDE_H);
    const y1 = clamp(Math.ceil(r.y + r.h + 2), 0, SLIDE_H);
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        const i = (y * SLIDE_W + x) * 3;
        out[i] = br; out[i + 1] = bg; out[i + 2] = bb;
      }
    }
  }
  void png;
  return sharp(out, { raw: { width: SLIDE_W, height: SLIDE_H, channels: 3 } }).png().toBuffer();
}

function runToElement(r: PdfRun, color: string): TextEl {
  const isHeading = r.fontSize >= 26;
  return {
    id: uid(),
    type: "text",
    text: r.text,
    x: clamp(Math.round(r.x), 0, SLIDE_W - 20),
    y: clamp(Math.round(r.y), 0, SLIDE_H - 8),
    // 打ち直しで多少伸びても収まるよう少し余裕を持たせる
    w: clamp(Math.round(r.w + r.fontSize), 24, SLIDE_W),
    h: clamp(Math.round(r.fontSize * 1.35), 12, SLIDE_H),
    fontSize: clamp(Math.round(r.fontSize), 8, 200),
    fontWeight: r.bold || isHeading ? 700 : 400,
    color,
    align: "left",
    lineHeight: 1.3,
    font: r.serif ? "heading" : isHeading ? "heading" : "body",
    name: isHeading ? "title" : "body",
  };
}

// (A) テキストPDFのページ: 元の位置・サイズのまま編集可能テキストを置く
async function buildVectorSlide(page: RasterPage, name: string): Promise<Slide> {
  const lines = groupLines(page.runs);
  const raw = await sharp(page.png).removeAlpha().resize(SLIDE_W, SLIDE_H, { fit: "fill" }).raw().toBuffer();
  const elements: TextEl[] = lines.map((l) => {
    const bg = ringColor(raw, l);
    const color = textColor(raw, l, bg, "#1B2421");
    return runToElement(l, color);
  });
  const clean = await paintOverText(page.png, lines, raw);
  const url = await saveAsset(`bg-${uid()}`, clean);
  return {
    id: uid(),
    name,
    background: { color: "token:bg", preset: "none", image: url },
    elements,
  };
}

function imageContent(jpeg: Buffer) {
  return {
    type: "image_url" as const,
    image_url: { url: `data:image/jpeg;base64,${jpeg.toString("base64")}`, detail: "high" as const },
  };
}

// (B) 画像のみPDFのページ: ビジョンOCR + gpt-imageで文字除去 + 組版エンジンで再配置
async function buildVisionSlide(
  png: Buffer,
  index: number,
  theme: ReturnType<typeof normalizeTheme>,
  textModel: string,
  editModel: string | undefined,
): Promise<Slide> {
  const small = await sharp(png).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
  const ext = await chatJSON<{ name?: string; texts?: { role?: string; text?: string }[]; zone?: unknown }>(
    textModel,
    EXTRACT_SYSTEM,
    [imageContent(small), { type: "text", text: "このスライドを構造化してください(座標は1280x720系)。" }],
    8000,
  );
  const texts = (ext.texts ?? [])
    .filter((t) => typeof t?.text === "string" && t.text.trim())
    .slice(0, 8)
    .map((t) => ({ role: t.role || "body", text: t.text! }));

  let clean = png;
  if (editModel) {
    const cleanRaw = await editImage(editModel, png, CLEAN_PROMPT, {});
    clean = await sharp(cleanRaw).resize(SLIDE_W, SLIDE_H, { fit: "fill" }).png().toBuffer();
  }
  const url = await saveAsset(`bg-${uid()}`, clean);
  const zone = sanitizeZone(ext.zone) ?? DEFAULT_ZONE;
  const elements = texts.length > 0 ? await applyContrast(typesetZone(texts, zone), texts, clean, theme) : [];
  return {
    id: uid(),
    name: ext.name || `ページ ${index + 1}`,
    background: { color: "token:bg", preset: "none", image: url },
    elements,
  };
}

async function asyncPool<T, R>(limit: number, items: T[], fn: (item: T, i: number) => Promise<R>): Promise<R[]> {
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

export async function importPdfDeck(pdf: Buffer): Promise<Deck> {
  const pages = await rasterizePages(pdf);
  if (pages.length === 0) throw new Error("PDFにページがありません");

  const hasOpenAI = openaiAvailable();
  const textModel = hasOpenAI ? await pickTextModel() : "";
  const editModels = hasOpenAI ? await pickTransparentImageModels() : [];
  const editModel = editModels[0];

  // テーマは1ページ目から(可能ならビジョンで、無ければ既定)
  let themeRaw: { title?: string; colors?: Record<string, string>; headingFont?: string; bodyFont?: string } = {};
  if (hasOpenAI) {
    try {
      const firstSmall = await sharp(pages[0].png).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
      themeRaw = await chatJSON(
        textModel,
        THEME_SYSTEM,
        [imageContent(firstSmall), { type: "text", text: "この資料のテーマを抽出してください。" }],
        4000,
      );
    } catch (e) {
      console.warn("pdf theme extraction failed:", e instanceof Error ? e.message : e);
    }
  }
  const theme = normalizeTheme(themeRaw);

  const slides = await asyncPool(2, pages, async (page, i): Promise<Slide> => {
    const chars = page.runs.reduce((n, r) => n + r.text.trim().length, 0);
    try {
      // テキストレイヤーが十分にあれば、無料・高精度な native 経路を使う
      if (chars >= VECTOR_MIN_CHARS) {
        return await buildVectorSlide(page, `ページ ${i + 1}`);
      }
      // 画像のみページ: ビジョンが使えなければ元画像をそのまま背景にする
      if (!hasOpenAI) {
        const url = await saveAsset(`bg-${uid()}`, page.png);
        return { id: uid(), name: `ページ ${i + 1}`, background: { color: "token:bg", preset: "none", image: url }, elements: [] };
      }
      return await buildVisionSlide(page.png, i, theme, textModel, editModel);
    } catch (e) {
      console.error(`pdf page ${i + 1} import failed:`, e);
      const url = await saveAsset(`bg-${uid()}`, page.png);
      return { id: uid(), name: `ページ ${i + 1}`, background: { color: "token:bg", preset: "none", image: url }, elements: [] };
    }
  });

  return { id: uid(), title: themeRaw.title || "インポートした資料", theme, slides };
}
