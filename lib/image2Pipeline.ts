import sharp from "sharp";
import { Deck, SLIDE_H, SLIDE_W, ShapeEl, Slide, SlideElement, TextEl, Theme, clamp, uid } from "./types";
import { normalizeTheme } from "./normalize";
import { readAsset, saveAsset } from "./assets";
import { ChatContent, chatJSON, generateImage, pickImageModel, pickTextModel } from "./openai";
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
  motif?: string; // このページの内容を表す視覚モチーフ(計画段階で決める)
  space?: string; // テキストを置く余白の位置: left|right|top|bottom|center
}

// 制作計画(構成案)。レビューを挟むため計画と生成を分離して公開する
export interface DeckPlan {
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
  lh?: number; // 行間(役割スケール由来)。未指定時は役割から推定
}

// 単一ページの再生成プロンプトでも同じ書き方を共有する
export const IMAGE_PROMPT_GUIDE = `# imagePrompt の書き方(最重要)
- 全ページ共通のスタイルガイド(配色のhex値・モチーフ・質感)を毎ページのプロンプト冒頭に同じ文で繰り返し、デッキ全体のトーンを揃える
- 【内容連動・最重要】そのページが伝える内容を表すモチーフを必ず描く。モチーフは**題材の実物が一目で認識できる具体的なフラットイラスト**を最優先にする(例: 傘のサービスなら「開いた傘・傘立て・雨粒と人」、コーヒーなら「カップ・豆・ドリッパー」、アプリなら「スマホ画面と人物」)。抽象図形だけの比喩は禁止し、抽象形(上昇する形・連結する形など)は実物イラストの補助として使う
- 構成の意味付け: 課題→実物が散らばる/困っている場面 / 3ステップ→実物が3つ連なる / 効果→実物と上昇する形。箇条書きの個数とイラストの数を揃えると内容との対応が伝わる
- モチーフはテキスト用余白の反対側に描く
- "Flat graphic presentation slide background design" として、写実ではなくエディトリアル/グラフィックデザインとして描かせる
- 必ず含める指示: "ABSOLUTELY NO text, letters, words, numbers, typography, or characters of any kind"
- 擬似文字の混入を防ぐ: UIモックアップ・偽スクリーンショット・書類・新聞・看板・ラベル付き図表など「文字が載っていそうなオブジェクト」をプロンプトに含めない
- テキストを載せる場所を意図的に空ける: "large clean empty negative space in the (位置)" を、そのページのtextsの量・役割に合わせて指定する
- 余白(ネガティブスペース)はフラットな無地または非常に淡いグラデーションにし、テキストの可読性を確保する
- 画像は3:2で生成されるが、上下がクロップされ中央の16:9だけが使われる。重要な構図要素は中央16:9に収める`;

const PLAN_SYSTEM = `あなたは一流のプレゼンテーションアートディレクターです。依頼から、画像生成モデル(gpt-image)でスライド背景をデザインするための制作計画をJSONで出力します。

出力(JSONのみ):
{
  "title": "資料タイトル",
  "theme": {
    "colors": { "brand": "#hex", "brandDark": "#hex", "brandSoft": "#hex", "accent": "#hex", "bg": "#hex", "surface": "#hex", "ink": "#hex", "muted": "#hex", "line": "#hex" },
    "headingFont": "'Noto Sans JP', sans-serif" など(候補: 'Noto Sans JP'/'Noto Serif JP'/'Zen Kaku Gothic New'/'M PLUS Rounded 1c'/'Shippori Mincho'/'Inter'/'Playfair Display'。欧文中心の資料では Inter(サンセリフ)/Playfair Display(セリフ)を優先),
    "bodyFont": 同上
  },
  "pages": [
    {
      "name": "ページ名",
      "motif": "(日本語)このページの内容を表す視覚モチーフの説明",
      "space": "left|right|top|bottom|center",
      "imagePrompt": "(英語)このページの背景デザインの画像生成プロンプト",
      "texts": [ { "role": "kicker|title|subtitle|body|stat|label", "text": "実際の文言" } ]
    }
  ]
}

# motif / space
- motif: ページの「伝える内容」から比喩を起こす(課題→散らばる断片、3ステップ→3つの連結形、など)。imagePromptはこのmotifを必ず描く
- space: テキスト一式を置く余白の位置。motifはその反対側に置く。ページ間で適度に変化させ、同じ側を3ページ以上続けない。テキストが多いページはleft/rightの縦長余白が安全

# 参考画像(与えられた場合)
- 参考画像から配色(主要色のhex)・質感・モチーフの方向性・トーンを読み取り、theme.colors と全ページ共通のスタイルガイドに反映する
- 画像内の文字・レイアウトはコピーせず、雰囲気だけを取り込む

${IMAGE_PROMPT_GUIDE}

# texts
- 【言語】texts・title・pages[].name は依頼文(テーマ)と同じ言語で書く。英語の依頼なら英語、日本語なら日本語
- 各ページ1メッセージ。title/kicker(短い英字ラベル)/body等を3〜6個
- 中身は具体的に(プレースホルダー禁止)。数値は仮であることが分かる表記`;

// ビジョンモデルには「最も大きく空いている領域」の特定だけを任せる。
// 文字組(サイズ・行数・間隔・整列)は実測ベースで決定的に行う方が崩れない。
const VISION_SYSTEM = `あなたはプレゼンテーションのアートディレクターです。スライド背景画像(1280x720)を見て、テキスト一式を載せるべき領域をJSONで返します。

出力(JSONのみ): { "containsText": boolean, "zone": { "x": 0-1280, "y": 0-720, "w": px, "h": px } }

ルール:
- zone: 背景の中で最も大きく綺麗に「空いている領域(ネガティブスペース)」。ここに見出し+本文の一式を組む
- 装飾・モチーフ・複雑な模様・コントラストの強い境界線の上は避け、フラットな(または淡いグラデーションの)領域を選ぶ
- スライドの端から最低64pxの余白を取る。zoneはできるだけ大きく取る(目安: 幅500px以上・高さ380px以上)
- テキスト量が多いほど大きなzoneが必要
- containsText: 背景画像そのものに文字・数字・ロゴ・崩れた擬似文字(文字のように見える模様)が描き込まれていればtrue。抽象的な図形・アイコンだけならfalse`;

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

// 参考画像(アセットURL)をビジョン入力用に縮小して読み込む
async function loadReferences(refs: string[] | undefined): Promise<Exclude<ChatContent, string>> {
  const out: Exclude<ChatContent, string> = [];
  for (const ref of (refs ?? []).slice(0, 3)) {
    const id = ref.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
    if (!id) continue;
    const buf = await readAsset(id);
    if (!buf) continue;
    const small = await sharp(buf).resize(640, 640, { fit: "inside" }).jpeg({ quality: 80 }).toBuffer();
    out.push({
      type: "image_url",
      image_url: { url: `data:image/jpeg;base64,${small.toString("base64")}`, detail: "low" },
    });
  }
  return out;
}

export async function generateImage2Deck(brief: GenerateBrief): Promise<Deck> {
  const plan = await makeDeckPlan(brief);
  return generateDeckFromPlan(plan, brief.pages);
}

// 1. 制作計画(構成案)を作る。feedback と previousPlan を渡すと修正版を出す
export async function makeDeckPlan(
  brief: GenerateBrief,
  feedback?: string,
  previousPlan?: DeckPlan,
): Promise<DeckPlan> {
  const textModel = await pickTextModel();
  // ページ数は指定があれば従い、なければ内容量からAIが提案する
  const pages = brief.pages ? Math.max(3, Math.min(brief.pages, 12)) : undefined;

  const planText = [
    `テーマ: ${brief.topic}`,
    pages
      ? `ページ数: ${pages}ページ`
      : `ページ数: 内容量に対して適切な枚数をあなたが決める(3〜12ページ)。1ページ1メッセージで詰め込まない。依頼文に枚数の希望が書かれていればそれを優先する`,
    brief.audience ? `想定読者: ${brief.audience}` : "",
    brief.tone ? `トーン: ${brief.tone}` : "",
    brief.notes ? `補足(必ず反映する): ${brief.notes}` : "",
    previousPlan
      ? `\n前回の構成案:\n${JSON.stringify(previousPlan)}\n\n上の構成案に対する修正指示: ${feedback || "(全体を改善)"}\n指示を反映した構成案を全ページ分あらためて出力する`
      : "",
  ]
    .filter(Boolean)
    .join("\n");
  const refs = await loadReferences(brief.references);
  const plan = await chatJSON<DeckPlan>(
    textModel,
    PLAN_SYSTEM,
    refs.length > 0
      ? [...refs, { type: "text" as const, text: `${planText}\n(添付は配色・トーンの参考画像)` }]
      : planText,
    32000,
  );
  plan.pages = (plan.pages ?? []).slice(0, pages ?? 12);
  return plan;
}

// 2. 承認済みの構成案からデッキを生成する
export async function generateDeckFromPlan(plan: DeckPlan, pagesLimit?: number): Promise<Deck> {
  const [textModel, imageModel] = await Promise.all([pickTextModel(), pickImageModel()]);
  const theme = normalizeTheme(plan.theme);
  const planPages = (plan.pages ?? []).slice(0, Math.max(3, Math.min(pagesLimit || 12, 12)));

  // ページ毎に 画像生成 → 切り出し → ビジョン解析 → 補正(並列・部分失敗許容)
  const slides = await asyncPool(3, planPages, (page, i) =>
    generateImage2Slide(page, theme, textModel, imageModel, i),
  );

  return { id: uid(), title: plan.title || "無題のデッキ", theme, slides };
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
    // 1回だけ作り直す。検知は余白ゾーン特定と同じビジョン呼び出しに相乗りさせる
    let cropped!: Buffer;
    let zone: Zone | null = null;
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
        const result = await chatJSON<{ containsText?: boolean; zone?: unknown }>(
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
                `この画像は1280x720のスライド背景です(座標はその系で回答)。載せるテキスト:\n` +
                texts.map((t, j) => `${j}: [${t.role}] ${t.text}`).join("\n") +
                (page.space ? `\n制作意図ではテキスト用余白は${page.space}側の想定。実際の画像を見て判断してください。` : ""),
            },
          ],
          8000,
        );
        zone = sanitizeZone(result.zone);
        containsText = result.containsText === true;
      } catch {
        zone = null;
      }
      if (!containsText) break;
      console.warn(`page ${index}: background contains text-like glyphs, regenerating`);
    }

    const assetId = `bg-${uid()}`;
    const url = await saveAsset(assetId, cropped);

    // ゾーン内に決定的に文字組し、背景の実測輝度で色とスクリムを決める
    const placements = typesetZone(texts, zone ?? zoneForSpace(page.space));
    const elements: SlideElement[] = await applyContrast(placements, texts, cropped, theme);

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

// ---- ゾーン内の決定的文字組 ----------------------------------------------
// カンプ(背景画像)の余白ゾーンに、役割別のタイポグラフィスケールで
// 上から順に組む。行数は全角/半角を区別した実測ベースの見積もりを使い、
// ゾーンからあふれる場合は全体を段階的に縮小する。

export interface Zone {
  x: number;
  y: number;
  w: number;
  h: number;
}

export const DEFAULT_ZONE: Zone = { x: 96, y: 110, w: 660, h: 510 };

// 制作計画の space(余白の位置)からフォールバック用ゾーンを引く。
// ビジョン解析が失敗してもページの設計意図に沿った位置に組める
export function zoneForSpace(space?: string): Zone {
  switch (space) {
    case "right":
      return { x: 624, y: 110, w: 560, h: 500 };
    case "top":
      return { x: 96, y: 72, w: 1088, h: 300 };
    case "bottom":
      return { x: 96, y: 348, w: 1088, h: 300 };
    case "center":
      return { x: 320, y: 140, w: 640, h: 440 };
    default: // left
      return DEFAULT_ZONE;
  }
}

export function sanitizeZone(z: unknown): Zone | null {
  if (!z || typeof z !== "object") return null;
  const o = z as Record<string, unknown>;
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : NaN);
  const rx = num(o.x);
  const ry = num(o.y);
  const rw = num(o.w);
  const rh = num(o.h);
  if ([rx, ry, rw, rh].some(Number.isNaN)) return null;
  const x = clamp(Math.round(rx), 32, SLIDE_W - 392);
  const y = clamp(Math.round(ry), 32, SLIDE_H - 272);
  const w = clamp(Math.round(rw), 360, SLIDE_W - x - 32);
  const h = clamp(Math.round(rh), 240, SLIDE_H - y - 32);
  return { x, y, w, h };
}

// 全角≈1.05em(字間・括弧込み)、半角≈0.55em として行幅を実測に近づける
function textEm(s: string): number {
  let em = 0;
  for (const ch of s) {
    em += /[ -ÿ｡-ﾟ]/.test(ch) ? 0.55 : 1.05;
  }
  return em;
}

function linesFor(text: string, fontSize: number, width: number): number {
  const emPerLine = Math.max(1, width / fontSize);
  return text
    .split("\n")
    .reduce((acc, seg) => acc + Math.max(1, Math.ceil(textEm(seg) / emPerLine)), 0);
}

// 折り返しの最終行に1文字相当だけ残るか(推定)。タイトルのサイズ選択で避ける
function hasOrphanLine(text: string, fontSize: number, width: number): boolean {
  const emPerLine = Math.max(1, width / fontSize);
  return text.split("\n").some((seg) => {
    const em = textEm(seg);
    if (em <= emPerLine) return false; // 1行に収まる
    const rem = em % emPerLine;
    return rem > 0 && rem <= 1.2;
  });
}

interface RoleSpec {
  size: number;
  weight: number;
  lh: number;
  gap: number; // 次の要素までの間隔
}

function specFor(t: PlanText, zoneW: number): RoleSpec {
  switch (t.role) {
    case "kicker":
      return { size: 15, weight: 700, lh: 1.4, gap: 22 };
    case "label":
      return { size: 14, weight: 700, lh: 1.5, gap: 12 };
    case "title": {
      // 3行以内に収まる最大サイズをスケールから選ぶ。
      // 最終行が1文字だけ落ちる(みなしご)サイズは見栄えが悪いので避ける
      const w = Math.min(zoneW, 760);
      const steps = [68, 60, 52, 46, 40, 36];
      const fits = steps.filter((s) => linesFor(t.text, s, w) <= 3);
      const size = fits.find((s) => !hasOrphanLine(t.text, s, w)) ?? fits[0] ?? 36;
      return { size, weight: 900, lh: 1.3, gap: 26 };
    }
    case "subtitle":
      return { size: textEm(t.text) > 30 ? 20 : 24, weight: 500, lh: 1.55, gap: 18 };
    case "stat":
      // 巨大数字は短いstatのときだけ。文章statは強調本文として組む
      return textEm(t.text) <= 14
        ? { size: 80, weight: 900, lh: 1.15, gap: 20 }
        : { size: 22, weight: 700, lh: 1.5, gap: 16 };
    default: // body
      return { size: 18, weight: 400, lh: 1.7, gap: 14 };
  }
}

function roleRank(role: string): number {
  if (role === "kicker") return 0;
  if (role === "title") return 1;
  if (role === "subtitle") return 2;
  if (role === "label") return 4; // 注釈は最後
  return 3; // body / stat は元の順序
}

export function typesetZone(texts: PlanText[], zone: Zone): Placement[] {
  const ordered = texts
    .map((t, i) => ({ t, i }))
    .sort((a, b) => roleRank(a.t.role) - roleRank(b.t.role) || a.i - b.i);

  // ゾーンが画面中央付近の広い領域なら中央揃え、それ以外は左揃え
  const centerX = zone.x + zone.w / 2;
  const centered = Math.abs(centerX - SLIDE_W / 2) < 140 && zone.x > 180 && zone.w > 560;

  const build = (scale: number) => {
    let y = zone.y;
    const items: Placement[] = [];
    for (const { t, i } of ordered) {
      const spec = specFor(t, zone.w);
      const size = Math.max(12, Math.round(spec.size * scale));
      // 可読性のため行長を抑える(見出しは広め、本文は約36文字相当まで)
      const w = Math.min(zone.w, t.role === "title" || t.role === "stat" ? 760 : 660);
      const h = Math.ceil(linesFor(t.text, size, w) * size * spec.lh) + 6;
      items.push({
        index: i,
        x: centered ? zone.x + Math.round((zone.w - w) / 2) : zone.x,
        y,
        w,
        h,
        fontSizePx: size,
        fontWeight: spec.weight,
        align: centered ? "center" : "left",
        colorHex: "",
        lh: spec.lh,
      });
      y += h + Math.round(spec.gap * scale);
    }
    return { items, bottom: y };
  };

  let scale = 1;
  let r = build(scale);
  while (r.bottom - zone.y > zone.h && scale > 0.72) {
    scale -= 0.07;
    r = build(scale);
  }
  // 余りが大きければ1/3だけ下げて光学的に落ち着かせる
  const slack = zone.h - (r.bottom - zone.y);
  if (slack > 60) {
    const off = Math.min(Math.round(slack / 3), 70);
    for (const p of r.items) p.y += off;
  }
  return r.items;
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
    lineHeight: p.lh ?? (isHeading ? 1.35 : 1.6),
    letterSpacing: t.role === "kicker" ? 3 : undefined,
    font: isHeading ? "heading" : "body",
    name: t.role,
  };
}

// 画像生成自体が失敗したとき(背景なし)の安全なデフォルト配置。
// 同じ文字組エンジンを既定ゾーンに適用し、指定色で組む
function fallbackLayout(texts: PlanText[], color = "#1B2421"): TextEl[] {
  return typesetZone(texts, DEFAULT_ZONE).map((p) =>
    placementToEl({ ...p, colorHex: color }, texts[p.index]),
  );
}
