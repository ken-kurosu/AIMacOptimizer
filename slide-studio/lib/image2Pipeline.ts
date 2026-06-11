import sharp from "sharp";
import { Deck, SLIDE_H, SLIDE_W, ShapeEl, Slide, SlideElement, TextEl, Theme, clamp, uid } from "./types";
import { normalizeTheme } from "./normalize";
import { saveAsset } from "./assets";
import { chatJSON, generateImage, pickImageModel, pickTextModel } from "./openai";
import { GenerateBrief } from "./mock";

// カンプ先行パイプライン(v1: 背景一枚絵 + HTMLテキスト層の2層構成)
//
//  1. GPT: アウトライン + アートディレクション + ページ毎の画像プロンプト(全てOpenAIで統一)
//  2. gpt-image系: ページ全面のデザイン画像を生成(文字なし・テキスト用の余白を指示)
//     → 3:2で生成されるため中央16:9を切り出して1280x720に
//  3. GPTビジョン: 生成画像を解析し、各テキストの配置(座標・サイズ・色)を決定
//  4. 決定的補正: テキスト量からの再レイアウト + 背景輝度の実測によるコントラスト保証
//  5. 編集可能なDeck(背景レイヤー=画像、テキスト=HTML要素)として組み立て
//
// 結果: 見た目はimage2のデザイン、テキスト・リンクは全て編集可能。

interface PlanText {
  role: string;
  text: string;
}

export interface PlanPage {
  name: string;
  imagePrompt: string;
  texts: PlanText[];
}

interface Plan {
  title: string;
  theme: {
    colors: Record<string, string>;
    headingFont: string;
    bodyFont: string;
  };
  pages: PlanPage[];
}

export interface Placement {
  index: number;
  x: number;
  y: number;
  w: number;
  h: number;
  fontSizePx: number;
  fontWeight: number;
  align: "left" | "center" | "right";
  colorHex: string;
}

// 単一ページの再生成プロンプトでも同じ書き方を共有する
export const IMAGE_PROMPT_GUIDE = `# imagePrompt の書き方(最重要)
- 全ページ共通のスタイルガイド(配色のhex値・モチーフ・質感)を毎ページのプロンプト冒頭に同じ文で繰り返し、デッキ全体のトーンを揃える
- "Flat graphic presentation slide background design" として、写実ではなくエディトリアル/グラフィックデザインとして描かせる
- 必ず含める指示: "ABSOLUTELY NO text, letters, words, numbers, typography, or characters of any kind"
- 擬似文字の混入を防ぐ: UIモックアップ・偽スクリーンショット・書類・新聞・看板・ラベル付き図表など「文字が載っていそうなオブジェクト」をプロンプトに含めない
- テキストを載せる場所を意図的に空ける: "large clean empty negative space in the (位置)" を、そのページのtextsの量・役割に合わせて指定する
- 構図はページごとに変化させる(左空け/中央空け/上空け、抽象形状、グラデーション、幾何学パターン、オーガニックな形)
- 余白(ネガティブスペース)はフラットな無地または非常に淡いグラデーションにし、テキストの可読性を確保する
- 画像は3:2で生成されるが、上下がクロップされ中央の16:9だけが使われる。重要な構図要素は中央16:9に収める`;

const PLAN_SYSTEM = `あなたは一流のプレゼンテーションアートディレクターです。依頼から、画像生成モデル(gpt-image)でスライド背景をデザインするための制作計画をJSONで出力します。

出力(JSONのみ):
{
  "title": "資料タイトル",
  "theme": {
    "colors": { "brand": "#hex", "brandDark": "#hex", "brandSoft": "#hex", "accent": "#hex", "bg": "#hex", "surface": "#hex", "ink": "#hex", "muted": "#hex", "line": "#hex" },
    "headingFont": "'Noto Sans JP', sans-serif" など(候補: 'Noto Sans JP'/'Noto Serif JP'/'Zen Kaku Gothic New'/'M PLUS Rounded 1c'/'Shippori Mincho'),
    "bodyFont": 同上
  },
  "pages": [
    {
      "name": "ページ名",
      "imagePrompt": "(英語)このページの背景デザインの画像生成プロンプト",
      "texts": [ { "role": "kicker|title|subtitle|body|stat|label", "text": "実際の文言" } ]
    }
  ]
}

${IMAGE_PROMPT_GUIDE}

# texts
- 各ページ1メッセージ。title/kicker(短い英字ラベル)/body等を3〜6個
- 中身は具体的に(プレースホルダー禁止)。数値は仮であることが分かる表記`;

const VISION_SYSTEM = `あなたはプレゼンテーションのレイアウトエンジンです。スライド背景画像(1280x720)と、配置すべきテキスト一覧を受け取り、各テキストの最適な配置をJSONで返します。

出力(JSONのみ): { "containsText": boolean, "items": [ { "index": 0, "x": 0-1280, "y": 0-720, "w": px, "h": px, "fontSizePx": px, "fontWeight": 400|500|700|800|900, "align": "left|center|right", "colorHex": "#hex" } ] }

containsText: 背景画像そのものに文字・数字・ロゴ・崩れた擬似文字(文字のように見える模様)が描き込まれている場合にtrue。抽象的な図形・アイコンだけならfalse

ルール:
- 背景の「空いている領域(ネガティブスペース)」にテキストを置く。背景の複雑な部分・コントラストの低い場所は避ける
- colorHexは直下の背景に対してコントラスト比4.5以上になる色。背景が暗ければ白系、明るければ濃色
- タイポグラフィのジャンプ率を高く: title 56-76px(weight 900)、kicker 14-16px(weight 700)、body 16-20px、stat 70-90px
- h は fontSizePx × 1.5 × 推定行数 以上。1行の文字数 ≈ w ÷ fontSizePx(日本語)
- 要素同士を重ねない。マージンは最低64px。整列(左揃えなら全要素のxを揃える)を守る
- indexは入力テキストの番号と1対1で対応させ、全テキストを配置する`;

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

export async function generateImage2Deck(brief: GenerateBrief): Promise<Deck> {
  const [textModel, imageModel] = await Promise.all([pickTextModel(), pickImageModel()]);
  const pages = Math.max(3, Math.min(brief.pages || 8, 12));

  // 1. 制作計画(アウトライン+アートディレクション+画像プロンプト)
  const plan = await chatJSON<Plan>(
    textModel,
    PLAN_SYSTEM,
    [
      `テーマ: ${brief.topic}`,
      `ページ数: ${pages}ページ`,
      brief.audience ? `想定読者: ${brief.audience}` : "",
      brief.tone ? `トーン: ${brief.tone}` : "",
    ]
      .filter(Boolean)
      .join("\n"),
    32000,
  );
  const theme = normalizeTheme(plan.theme);
  const planPages = (plan.pages ?? []).slice(0, pages);

  // 2〜4. ページ毎に 画像生成 → 切り出し → ビジョン解析 → 補正(並列・部分失敗許容)
  const slides = await asyncPool(3, planPages, (page, i) =>
    generateImage2Slide(page, theme, textModel, imageModel, i),
  );

  return { id: uid(), title: plan.title || brief.topic, theme, slides };
}

// 1ページ分の生成。デッキ一括生成と「このページだけ再生成」の両方から使う。
// fallbackOnError: 一括生成では失敗ページを無地スライドに倒すが、
// 単一ページ再生成では元のスライドを残したいので例外をそのまま投げる
export async function generateImage2Slide(
  page: PlanPage,
  theme: Theme,
  textModel: string,
  imageModel: string,
  index = 0,
  fallbackOnError = true,
): Promise<Slide> {
  const texts = (page.texts ?? []).slice(0, 8);
  try {
    // 画像生成→ビジョン解析。背景に文字(化けた擬似文字含む)が混入していたら
    // 1回だけ作り直す。検知はレイアウト解析と同じビジョン呼び出しに相乗りさせる
    let cropped!: Buffer;
    let placements: Placement[] = [];
    for (let attempt = 0; attempt < 2; attempt++) {
      const prompt =
        attempt === 0
          ? page.imagePrompt
          : `${page.imagePrompt}\n\nIMPORTANT: The previous attempt contained text or letter-like glyphs. ` +
            `Render ABSOLUTELY NO text, letters, numbers, logos, UI screenshots, or any character-like marks anywhere.`;
      const raw = await generateImage(imageModel, prompt);
      // 3:2 (1536x1024) → 中央16:9を切り出して1280x720へ
      cropped = await sharp(raw)
        .extract({ left: 0, top: 80, width: 1536, height: 864 })
        .resize(1280, 720)
        .png()
        .toBuffer();

      // ビジョン解析用に縮小(トークン節約)。座標系は1280x720で回答させる
      const small = await sharp(cropped).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
      let containsText = false;
      try {
        const result = await chatJSON<{ containsText?: boolean; items: Placement[] }>(
          textModel,
          VISION_SYSTEM,
          [
            {
              type: "image_url",
              image_url: { url: `data:image/jpeg;base64,${small.toString("base64")}`, detail: "high" },
            },
            {
              type: "text",
              text:
                `この画像は1280x720のスライド背景です(座標はその系で回答)。配置するテキスト:\n` +
                texts.map((t, j) => `${j}: [${t.role}] ${t.text}`).join("\n"),
            },
          ],
          8000,
        );
        placements = result.items ?? [];
        containsText = result.containsText === true;
      } catch {
        placements = [];
      }
      if (!containsText) break;
      console.warn(`page ${index}: background contains text-like glyphs, regenerating`);
    }

    const assetId = `bg-${uid()}`;
    const url = await saveAsset(assetId, cropped);

    const elements: SlideElement[] =
      placements.length > 0
        ? await applyContrast(refinePlacements(placements, texts), texts, cropped, theme)
        : fallbackLayout(texts);

    return {
      id: uid(),
      name: page.name || `スライド ${index + 1}`,
      background: { color: "token:bg", preset: "none", image: url },
      elements,
    };
  } catch (e) {
    if (!fallbackOnError) throw e;
    console.error(`page ${index} image generation failed:`, e);
    // 画像生成失敗ページは無地+デフォルトレイアウトに倒す
    return {
      id: uid(),
      name: page.name || `スライド ${index + 1}`,
      background: { color: "token:brandDark", preset: "mesh" },
      elements: fallbackLayout(texts, "#FFFFFF"),
    };
  }
}

// ビジョン解析の配置をそのまま信用せず、テキスト量から決定的に補正する。
// 実機検証で「hの過小見積もり→要素同士の重なり」「長文statへの巨大フォント」が頻発した。
function refinePlacements(placements: Placement[], texts: PlanText[]): Placement[] {
  const MARGIN = 24;
  const out = placements
    .filter((p) => texts[p.index])
    .map((p) => ({ ...p }))
    .sort((a, b) => a.y - b.y || a.x - b.x);

  for (const p of out) {
    const t = texts[p.index];
    p.x = clamp(Math.round(p.x), 0, SLIDE_W - 160);
    p.w = clamp(Math.round(p.w), 120, SLIDE_W - p.x - 48);
    p.y = clamp(Math.round(p.y), MARGIN, SLIDE_H - 72);

    // 役割別のフォント上限。statの巨大文字は短い数字のときだけ許す
    const longStat = t.role === "stat" && t.text.length > 12;
    const maxFont =
      t.role === "title" ? 76
      : t.role === "stat" ? (longStat ? 28 : 96)
      : t.role === "subtitle" ? 28
      : t.role === "kicker" || t.role === "label" ? 18
      : 22;
    p.fontSizePx = clamp(Math.round(p.fontSizePx) || 18, 12, maxFont);

    // 推定必要高さが役割別の上限を超える間はフォントを縮め、hは推定値で引き直す
    const maxH = t.role === "title" ? 330 : t.role === "stat" ? 220 : 180;
    while (p.fontSizePx > 14 && estimateHeight(t, p.fontSizePx, p.w) > maxH) {
      p.fontSizePx -= 2;
    }
    p.h = estimateHeight(t, p.fontSizePx, p.w) + 8;
  }

  // x範囲が重なる要素同士の縦の重なりを上から順に下へ送って解消
  for (let i = 1; i < out.length; i++) {
    for (let j = 0; j < i; j++) {
      const a = out[j];
      const b = out[i];
      const xOverlap = a.x < b.x + b.w && b.x < a.x + a.w;
      if (xOverlap && b.y < a.y + a.h + MARGIN) b.y = a.y + a.h + MARGIN;
    }
  }

  // 下端からあふれた分は、上端の余裕の範囲で全体を上に詰める
  const bottom = Math.max(...out.map((p) => p.y + p.h));
  if (bottom > SLIDE_H - MARGIN) {
    const slack = Math.min(...out.map((p) => p.y)) - MARGIN;
    const shift = Math.min(bottom - (SLIDE_H - MARGIN), Math.max(slack, 0));
    if (shift > 0) for (const p of out) p.y -= shift;
  }
  return out;
}

// 日本語前提の必要高さ見積もり(字間・括弧で実効文字幅はfontSizeの約1.1倍)
function estimateHeight(t: PlanText, fontSize: number, w: number): number {
  const perLine = Math.max(1, Math.floor(w / (fontSize * 1.1)));
  const lines = Math.ceil(t.text.length / perLine);
  const lh = t.role === "title" || t.role === "stat" ? 1.35 : 1.6;
  return Math.ceil(lines * fontSize * lh);
}

// ---- コントラスト保証 ----------------------------------------------------
// ビジョンモデルの色選択を信用せず、背景画像の文字領域の輝度を実測して
// 足りなければ白/インクの良い方に置き換え、それでも不足 or 背景が騒がしい
// 場合は半透明のスクリム(角丸rect)をテキストの下に敷く。スクリムも通常の
// 図形要素なのでエディタで移動・削除できる。

const STATS_W = 128;
const STATS_H = 72;

interface RegionStats {
  lum: number; // 平均相対輝度 0-1
  std: number; // 輝度の標準偏差(騒がしさ)
}

function regionStats(data: Buffer, x: number, y: number, w: number, h: number): RegionStats {
  const x0 = clamp(Math.floor((x / SLIDE_W) * STATS_W), 0, STATS_W - 1);
  const x1 = clamp(Math.ceil(((x + w) / SLIDE_W) * STATS_W), x0 + 1, STATS_W);
  const y0 = clamp(Math.floor((y / SLIDE_H) * STATS_H), 0, STATS_H - 1);
  const y1 = clamp(Math.ceil(((y + h) / SLIDE_H) * STATS_H), y0 + 1, STATS_H);
  let sum = 0;
  let sumSq = 0;
  let n = 0;
  for (let yy = y0; yy < y1; yy++) {
    for (let xx = x0; xx < x1; xx++) {
      const i = (yy * STATS_W + xx) * 3;
      const l = relLuminance(data[i], data[i + 1], data[i + 2]);
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  const lum = sum / n;
  return { lum, std: Math.sqrt(Math.max(0, sumSq / n - lum * lum)) };
}

function relLuminance(r: number, g: number, b: number): number {
  const f = (c: number) => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}

function hexLuminance(hex: string): number {
  const m = /^#([0-9a-fA-F]{6})$/.exec(hex);
  if (!m) return 1;
  const v = parseInt(m[1], 16);
  return relLuminance((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
}

function contrastRatio(l1: number, l2: number): number {
  const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (hi + 0.05) / (lo + 0.05);
}

const BUSY_STD = 0.16; // これ以上輝度がばらつく領域は「騒がしい」とみなす

// exportは検証スクリプト/テスト用
export async function applyContrast(
  placements: Placement[],
  texts: PlanText[],
  cropped: Buffer,
  theme: Theme,
): Promise<SlideElement[]> {
  // nearestで縮小=実ピクセルのサンプリング。平均化すると細かい模様の
  // 騒がしさ(輝度分散)が消えてスクリム判定が働かなくなる
  const data = await sharp(cropped)
    .resize(STATS_W, STATS_H, { kernel: "nearest" })
    .raw()
    .toBuffer();
  const ink = theme.colors.ink;
  const els: TextEl[] = [];
  const scrimBoxes: { x0: number; y0: number; x1: number; y1: number; dark: boolean }[] = [];

  for (const p of placements) {
    const t = texts[p.index];
    const s = regionStats(data, p.x, p.y, p.w, p.h);
    // WCAG: 大きい文字(32px以上)は3.0、それ以外は4.5を要求
    const required = p.fontSizePx >= 32 ? 3 : 4.5;

    let color = /^#[0-9a-fA-F]{6}$/.test(p.colorHex) ? p.colorHex : "#FFFFFF";
    if (contrastRatio(hexLuminance(color), s.lum) < required) {
      color =
        contrastRatio(1, s.lum) >= contrastRatio(hexLuminance(ink), s.lum) ? "#FFFFFF" : ink;
    }
    const ok = contrastRatio(hexLuminance(color), s.lum) >= required;
    if (!ok || s.std > BUSY_STD) {
      scrimBoxes.push({
        x0: p.x - 20,
        y0: p.y - 14,
        x1: p.x + p.w + 20,
        y1: p.y + p.h + 14,
        dark: hexLuminance(color) > 0.5, // 白文字なら暗いスクリム
      });
    }
    p.colorHex = color;
    els.push(placementToEl(p, t));
  }

  // 近接する同トーンのスクリムは1枚にまとめる(ページがパッチワークになるのを防ぐ)
  const merged: typeof scrimBoxes = [];
  for (const b of scrimBoxes) {
    const hit = merged.find(
      (m) =>
        m.dark === b.dark &&
        m.x0 < b.x1 + 24 &&
        b.x0 < m.x1 + 24 &&
        m.y0 < b.y1 + 24 &&
        b.y0 < m.y1 + 24,
    );
    if (hit) {
      hit.x0 = Math.min(hit.x0, b.x0);
      hit.y0 = Math.min(hit.y0, b.y0);
      hit.x1 = Math.max(hit.x1, b.x1);
      hit.y1 = Math.max(hit.y1, b.y1);
    } else {
      merged.push({ ...b });
    }
  }
  const scrims: ShapeEl[] = merged.map((b) => ({
    id: uid(),
    type: "shape",
    shape: "rect",
    x: clamp(Math.round(b.x0), 0, SLIDE_W),
    y: clamp(Math.round(b.y0), 0, SLIDE_H),
    w: Math.round(Math.min(b.x1, SLIDE_W) - Math.max(b.x0, 0)),
    h: Math.round(Math.min(b.y1, SLIDE_H) - Math.max(b.y0, 0)),
    fill: b.dark ? theme.colors.brandDark : "#FFFFFF",
    opacity: b.dark ? 0.66 : 0.8,
    radius: 16,
    name: "scrim",
  }));

  return [...scrims, ...els];
}

function placementToEl(p: Placement, t: PlanText): TextEl {
  const isHeading = t.role === "title" || t.role === "stat";
  return {
    id: uid(),
    type: "text",
    text: t.text,
    x: Math.round(p.x),
    y: Math.round(p.y),
    w: Math.round(p.w),
    h: Math.round(p.h),
    fontSize: p.fontSizePx,
    fontWeight: p.fontWeight,
    color: /^#[0-9a-fA-F]{6}$/.test(p.colorHex) ? p.colorHex : "#FFFFFF",
    align: p.align ?? "left",
    lineHeight: isHeading ? 1.35 : 1.6,
    letterSpacing: t.role === "kicker" ? 3 : undefined,
    font: isHeading ? "heading" : "body",
    name: t.role,
  };
}

// ビジョン解析が失敗したときの安全なデフォルト配置
function fallbackLayout(texts: PlanText[], color = "#1B2421"): TextEl[] {
  let y = 180;
  return texts.map((t) => {
    const isTitle = t.role === "title";
    const fontSize = isTitle ? 56 : t.role === "kicker" ? 14 : 18;
    const h = isTitle ? 160 : 60;
    const el: TextEl = {
      id: uid(),
      type: "text",
      text: t.text,
      x: 80,
      y,
      w: 1120,
      h,
      fontSize,
      fontWeight: isTitle ? 900 : t.role === "kicker" ? 700 : 400,
      color,
      align: "left",
      lineHeight: isTitle ? 1.35 : 1.6,
      letterSpacing: t.role === "kicker" ? 3 : undefined,
      font: isTitle ? "heading" : "body",
      name: t.role,
    };
    y += h + 24;
    return el;
  });
}
