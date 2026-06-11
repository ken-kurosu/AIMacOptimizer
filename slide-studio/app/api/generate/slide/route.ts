import { normalizeTheme } from "@/lib/normalize";
import { IMAGE_PROMPT_GUIDE, PlanPage, generateImage2Slide } from "@/lib/image2Pipeline";
import { chatJSON, openaiAvailable, pickImageModel, pickTextModel } from "@/lib/openai";

export const maxDuration = 180;

// 「このページだけimage2で再デザイン」。既存スライドのテキストとデッキのテーマを
// 受け取り、背景画像の生成からビジョン配置・コントラスト補正までを1ページ分だけ行う。

const PROMPT_SYSTEM = `あなたは一流のプレゼンテーションアートディレクターです。スライド1ページ分の背景デザインについて、画像生成モデル(gpt-image)向けの英語プロンプトをJSONで出力します。

出力(JSONのみ): { "imagePrompt": "(英語)" }

${IMAGE_PROMPT_GUIDE}`;

interface SlideBrief {
  topic?: string;
  theme: unknown;
  page: {
    name?: string;
    imagePrompt?: string;
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
  const texts = (brief.page.texts ?? [])
    .filter((t) => typeof t?.text === "string" && t.text.trim())
    .slice(0, 8)
    .map((t) => ({ role: t.role || "body", text: t.text! }));

  try {
    const [textModel, imageModel] = await Promise.all([pickTextModel(), pickImageModel()]);

    let imagePrompt = brief.page.imagePrompt;
    if (!imagePrompt) {
      const result = await chatJSON<{ imagePrompt: string }>(
        textModel,
        PROMPT_SYSTEM,
        [
          brief.topic ? `資料のテーマ: ${brief.topic}` : "",
          brief.page.name ? `ページ名: ${brief.page.name}` : "",
          `デッキの配色(この色を必ずスタイルガイドとして使う): ${JSON.stringify(theme.colors)}`,
          `このページに載せるテキスト:\n${texts.map((t) => `- [${t.role}] ${t.text}`).join("\n")}`,
        ]
          .filter(Boolean)
          .join("\n"),
        8000,
      );
      imagePrompt = result.imagePrompt;
      if (!imagePrompt) throw new Error("no imagePrompt in plan response");
    }

    const page: PlanPage = { name: brief.page.name ?? "", imagePrompt, texts };
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
