import Anthropic from "@anthropic-ai/sdk";
import { generateMockDeck } from "@/lib/mock";
import { normalizeDeck } from "@/lib/normalize";

export const maxDuration = 300;

interface Brief {
  topic: string;
  pages: number;
  audience?: string;
  tone?: string;
}

const SYSTEM_PROMPT = `あなたは一流のプレゼンテーションデザイナー兼アートディレクターです。
依頼内容から、デザイン性の高いスライドデッキをJSONで生成します。

# 出力形式
コードフェンスや説明文は一切付けず、次の構造のJSONオブジェクトのみを出力してください。

{
  "title": "資料タイトル",
  "theme": {
    "colors": {
      "brand": "#hex", "brandDark": "#hex", "brandSoft": "#hex",
      "accent": "#hex", "bg": "#hex", "surface": "#hex",
      "ink": "#hex", "muted": "#hex", "line": "#hex"
    },
    "headingFont": "<フォント>", "bodyFont": "<フォント>"
  },
  "slides": [
    {
      "name": "ページ名",
      "background": { "color": "<色>", "preset": "<プリセット>" },
      "elements": [ <要素の配列> ]
    }
  ]
}

要素は3種類:
- テキスト: { "type": "text", "x", "y", "w", "h", "text", "fontSize", "fontWeight", "color", "align": "left|center|right", "lineHeight", "letterSpacing"?, "font": "heading|body", "opacity"?, "link"? }
- 図形: { "type": "shape", "x", "y", "w", "h", "shape": "rect|ellipse|line", "fill", "stroke"?, "strokeWidth"?, "radius"?, "opacity"? }
- 画像は使わない(画像URLが手元にないため)

# 語彙の制約
- 座標系: 1280x720固定。x,y,w,h はその範囲の数値
- 色: "#rrggbb" か、テーマトークン参照 "token:brand" / "token:brandDark" / "token:brandSoft" / "token:accent" / "token:bg" / "token:surface" / "token:ink" / "token:muted" / "token:line"。要素の色は原則トークン参照にする(テーマ変更に追従させるため)
- background.preset: "none" | "mesh" | "blobs" | "diagonal" | "grid" | "waves" | "dots" | "frame"
- フォント: "'Noto Sans JP', sans-serif" | "'Noto Serif JP', serif" | "'Zen Kaku Gothic New', sans-serif" | "'M PLUS Rounded 1c', sans-serif" | "'Shippori Mincho', serif"

# アートディレクション
1. まずトーンと題材に合うテーマ(9色+フォントペア)を決める。bgとinkのコントラストを十分確保。brandSoftはbrandのごく淡い色(背景上の装飾に使える濃さ)にする
2. 【最重要】「カードの羅列」を禁止する。surface塗り+枠線+角丸の箱を並べる構成は使わない(使ってもデッキ全体で1ページまで)。生成AIスライドにありがちな均一なカードグリッドは退屈で安っぽい。代わりにエディトリアルな構成を使う:
   - 大きな余白と非対称構成。タイポグラフィのジャンプ率を高く(例: 72 / 40 / 22 / 15)
   - リストは「番号(01,02…のtoken:brand太字)+見出し+本文+細い区切り線(rect h=1, token:line)」で組む
   - 統計・数値は枠なしの巨大数字(fontSize 80-90, token:brand, font:heading)+上に細罫線+短いアクセントバー
   - セクション扉・引用・クロージングは全面塗り(token:brandDark や token:brand)にして文字は#FFFFFF。巨大なゴースト数字(fontSize 300-380, opacity 0.2-0.35)を背景に置く
   - 比較は画面を縦半分に塗り分ける(x=0,w=600,h=720のrectをtoken:brandDarkで置き、左は白文字・右はink)
   - 画面外にはみ出す大きなellipse(token:brandSoftやopacity 0.2-0.4のtoken:brand)を装飾パーツとして1-2個置く
   - 各ページ左上にキッカー(英字ラベル fontSize 14, fontWeight 700, letterSpacing 3, token:brand)
3. ページごとにレイアウトを変える。同じ構成のページを3回以上続けない
4. 文字あふれ防止: テキストのhは fontSize × lineHeight × 行数 より大きく取る。1行に入る文字数 ≈ w ÷ fontSize(日本語)。本文fontSizeは15-20、見出しは32-72
5. 構成: 表紙 → アジェンダ → セクション扉と内容ページ → まとめ/クロージング。1ページ1メッセージ
6. 中身は具体的に書く(プレースホルダー禁止)。数値を使う場合は仮であることが分かる表記にする`;

export async function POST(req: Request) {
  let brief: Brief;
  try {
    brief = (await req.json()) as Brief;
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }
  const pages = Math.max(3, Math.min(brief.pages || 8, 20));

  if (!process.env.ANTHROPIC_API_KEY) {
    return Response.json({ mode: "demo", deck: generateMockDeck({ ...brief, pages }) });
  }

  try {
    const client = new Anthropic();
    const stream = client.messages.stream({
      model: "claude-opus-4-8",
      max_tokens: 64000,
      thinking: { type: "adaptive" },
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            `テーマ: ${brief.topic}`,
            `ページ数: ${pages}ページ`,
            brief.audience ? `想定読者: ${brief.audience}` : "",
            brief.tone ? `トーン: ${brief.tone}` : "",
          ]
            .filter(Boolean)
            .join("\n"),
        },
      ],
    });
    const message = await stream.finalMessage();
    const text = message.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("");
    const deck = normalizeDeck(extractJson(text));
    return Response.json({ mode: "claude", deck });
  } catch (e) {
    console.error("generate failed, falling back to demo:", e);
    return Response.json({
      mode: "demo",
      warning: e instanceof Error ? e.message : "generation failed",
      deck: generateMockDeck({ ...brief, pages }),
    });
  }
}

function extractJson(text: string): unknown {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no JSON in response");
  return JSON.parse(candidate.slice(start, end + 1));
}
