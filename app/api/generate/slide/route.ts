import { normalizeTheme } from "@/lib/normalize";
import { IMAGE_PROMPT_GUIDE, PlanPage, generateImage2Slide } from "@/lib/image2Pipeline";
import { chatJSON, openaiAvailable, pickImageModel, pickTextModel } from "@/lib/openai";

export const maxDuration = 180;

// 1ページ分のimage2生成。2つの使い方がある:
//  - 再デザイン: 既存スライドの texts を渡す(テキスト維持で背景と配置を作り直す)
//  - AIページ追加: texts なしで description を渡す(ページ名・テキストも生成する)

const PROMPT_SYSTEM = `あなたは一流のプレゼンテーションアートディレクターです。スライド1ページ分の背景デザインについて、画像生成モデル(gpt-image)向けの英語プロンプトをJSONで出力します。

出力(JSONのみ): { "motif": "(日本語)このページの内容を表す視覚モチーフ", "space": "left|right|top|bottom|center", "imagePrompt": "(英語)" }

motifはページのテキスト(伝える内容)から比喩を起こし、imagePromptで必ず描く。spaceはテキスト一式を置く余白の位置で、motifはその反対側に置く。

${IMAGE_PROMPT_GUIDE}`;

const NEW_PAGE_SYSTEM = `あなたは一流のプレゼンテーションアートディレクターです。既存のデッキに追加する1ページについて、ページ名・テキスト・背景画像プロンプトをJSONで出力します。

出力(JSONのみ): { "name": "ページ名", "motif": "(日本語)内容を表す視覚モチーフ", "space": "left|right|top|bottom|center", "imagePrompt": "(英語)", "texts": [ { "role": "kicker|title|subtitle|body|stat|label", "text": "実際の文言" } ] }

motifはページの「伝える内容」から比喩を起こし、imagePromptで必ず描く。spaceはテキスト一式を置く余白の位置で、motifはその反対側に置く。

${IMAGE_PROMPT_GUIDE}

# texts
- 1ページ1メッセージ。title/kicker(短い英字ラベル)/body等を3〜6個
- 中身は具体的に(プレースホルダー禁止)。数値は仮であることが分かる表記`;

interface SlideBrief {
  topic?: string;
  theme: unknown;
  page: {
    name?: string;
    imagePrompt?: string;
    description?: string;
    texts?: { role?: string; text?: string }[];
  };
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY が未設定です" }, { status: 400 });
  }

  let brief: SlideBrief;
  try {
    brief = (await req.json()) as SlideBrief;
    if (!brief?.page) throw new Error("no page");
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }

  const theme = normalizeTheme(brief.theme);
  let texts = (brief.page.texts ?? [])
    .filter((t) => typeof t?.text === "string" && t.text.trim())
    .slice(0, 8)
    .map((t) => ({ role: t.role || "body", text: t.text! }));
  const description = brief.page.description?.trim();
  if (texts.length === 0 && !description) {
    return Response.json({ error: "texts か description のどちらかが必要です" }, { status: 400 });
  }

  try {
    const [textModel, imageModel] = await Promise.all([pickTextModel(), pickImageModel()]);
    let name = brief.page.name ?? "";
    let imagePrompt = brief.page.imagePrompt;
    let space: string | undefined;

    if (texts.length === 0) {
      // AIページ追加: 内容の説明からページ名・テキスト・画像プロンプトを起こす
      const planned = await chatJSON<{
        name?: string;
        imagePrompt: string;
        space?: string;
        texts?: { role?: string; text?: string }[];
      }>(
        textModel,
        NEW_PAGE_SYSTEM,
        [
          brief.topic ? `資料のテーマ: ${brief.topic}` : "",
          `デッキの配色(この色を必ずスタイルガイドとして使う): ${JSON.stringify(theme.colors)}`,
          `追加するページの内容: ${description}`,
        ]
          .filter(Boolean)
          .join("\n"),
        16000,
      );
      texts = (planned.texts ?? [])
        .filter((t) => typeof t?.text === "string" && t.text.trim())
        .slice(0, 8)
        .map((t) => ({ role: t.role || "body", text: t.text! }));
      if (texts.length === 0) throw new Error("no texts in plan response");
      name = planned.name || name;
      imagePrompt = planned.imagePrompt;
      space = planned.space;
    }

    if (!imagePrompt) {
      const result = await chatJSON<{ imagePrompt: string; space?: string }>(
        textModel,
        PROMPT_SYSTEM,
        [
          brief.topic ? `資料のテーマ: ${brief.topic}` : "",
          name ? `ページ名: ${name}` : "",
          `デッキの配色(この色を必ずスタイルガイドとして使う): ${JSON.stringify(theme.colors)}`,
          `このページに載せるテキスト:\n${texts.map((t) => `- [${t.role}] ${t.text}`).join("\n")}`,
        ]
          .filter(Boolean)
          .join("\n"),
        8000,
      );
      imagePrompt = result.imagePrompt;
      space = result.space;
      if (!imagePrompt) throw new Error("no imagePrompt in plan response");
    }

    const page: PlanPage = { name, imagePrompt, texts, space };
    const slide = await generateImage2Slide(page, theme, textModel, imageModel, 0, false);
    return Response.json({ slide });
  } catch (e) {
    console.error("slide regeneration failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "slide regeneration failed" },
      { status: 502 },
    );
  }
}
