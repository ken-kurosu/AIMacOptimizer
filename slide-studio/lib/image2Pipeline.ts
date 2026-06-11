import sharp from "sharp";
import { Deck, Slide, TextEl, uid } from "./types";
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
//  4. 編集可能なDeck(背景レイヤー=画像、テキスト=HTML要素)として組み立て
//
// 結果: 見た目はimage2のデザイン、テキスト・リンクは全て編集可能。

interface PlanText {
  role: string;
  text: string;
}

interface PlanPage {
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

interface Placement {
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

# imagePrompt の書き方(最重要)
- 全ページ共通のスタイルガイド(配色のhex値・モチーフ・質感)を毎ページのプロンプト冒頭に同じ文で繰り返し、デッキ全体のトーンを揃える
- "Flat graphic presentation slide background design" として、写実ではなくエディトリアル/グラフィックデザインとして描かせる
- 必ず含める指示: "ABSOLUTELY NO text, letters, words, numbers, typography, or characters of any kind"
- テキストを載せる場所を意図的に空ける: "large clean empty negative space in the (位置)" を、そのページのtextsの量・役割に合わせて指定する
- 構図はページごとに変化させる(左空け/中央空け/上空け、抽象形状、グラデーション、幾何学パターン、オーガニックな形)
- 余白(ネガティブスペース)はフラットな無地または非常に淡いグラデーションにし、テキストの可読性を確保する
- 画像は3:2で生成されるが、上下がクロップされ中央の16:9だけが使われる。重要な構図要素は中央16:9に収める

# texts
- 各ページ1メッセージ。title/kicker(短い英字ラベル)/body等を3〜6個
- 中身は具体的に(プレースホルダー禁止)。数値は仮であることが分かる表記`;

const VISION_SYSTEM = `あなたはプレゼンテーションのレイアウトエンジンです。スライド背景画像(1280x720)と、配置すべきテキスト一覧を受け取り、各テキストの最適な配置をJSONで返します。

出力(JSONのみ): { "items": [ { "index": 0, "x": 0-1280, "y": 0-720, "w": px, "h": px, "fontSizePx": px, "fontWeight": 400|500|700|800|900, "align": "left|center|right", "colorHex": "#hex" } ] }

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

  // 2 + 3. ページ毎に 画像生成 → 切り出し → ビジョン解析(並列・部分失敗許容)
  const slides = await asyncPool(3, planPages, async (page, i): Promise<Slide> => {
    const texts = (page.texts ?? []).slice(0, 8);
    try {
      const raw = await generateImage(imageModel, page.imagePrompt);
      // 3:2 (1536x1024) → 中央16:9を切り出して1280x720へ
      const cropped = await sharp(raw)
        .extract({ left: 0, top: 80, width: 1536, height: 864 })
        .resize(1280, 720)
        .png()
        .toBuffer();
      const assetId = `bg-${uid()}`;
      const url = await saveAsset(assetId, cropped);

      // ビジョン解析用に縮小(トークン節約)。座標系は1280x720で回答させる
      const small = await sharp(cropped).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
      let placements: Placement[] = [];
      try {
        const result = await chatJSON<{ items: Placement[] }>(
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
      } catch {
        placements = [];
      }

      const elements: TextEl[] =
        placements.length > 0
          ? placements
              .filter((p) => texts[p.index])
              .map((p) => placementToEl(p, texts[p.index]))
          : fallbackLayout(texts);

      return {
        id: uid(),
        name: page.name || `スライド ${i + 1}`,
        background: { color: "token:bg", preset: "none", image: url },
        elements,
      };
    } catch (e) {
      console.error(`page ${i} image generation failed:`, e);
      // 画像生成失敗ページは無地+デフォルトレイアウトに倒す
      return {
        id: uid(),
        name: page.name || `スライド ${i + 1}`,
        background: { color: "token:brandDark", preset: "mesh" },
        elements: fallbackLayout(texts, "#FFFFFF"),
      };
    }
  });

  return { id: uid(), title: plan.title || brief.topic, theme, slides };
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
