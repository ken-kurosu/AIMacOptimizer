import { chatJSON, openaiAvailable, pickTextModel } from "@/lib/openai";

export const maxDuration = 60;

// 要素単位の差し替え(テキスト): 選択中のテキストをAIで磨く/書き換える

const SYSTEM = `あなたはプレゼンテーション資料のコピーライターです。スライド上の1つのテキスト要素を、指示に沿って書き直します。

出力(JSONのみ): { "text": "書き直した文言" }

ルール:
- 出力は元の文言と同じ言語で書く(指示で言語変更を求められた場合を除く)
- 指示がなければ「より明確で、短く、印象に残る」方向に磨く
- 文字数は元と同程度(±3割)に収める(レイアウトを壊さないため)
- スライドの文言なので、語尾や体裁は元のトーンを保つ。改行も元の構造を尊重する
- 出力は文言そのものだけ。説明や引用符は付けない`;

interface RewriteBrief {
  text?: string;
  instruction?: string;
  context?: string; // デッキタイトルやページ名
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY is not configured" }, { status: 400 });
  }
  let brief: RewriteBrief;
  try {
    brief = (await req.json()) as RewriteBrief;
    if (!brief.text?.trim()) throw new Error("no text");
  } catch {
    return Response.json({ error: "text is required" }, { status: 400 });
  }
  try {
    const result = await chatJSON<{ text?: string }>(
      await pickTextModel(),
      SYSTEM,
      [
        brief.context ? `資料の文脈: ${brief.context}` : "",
        `元の文言: ${brief.text}`,
        brief.instruction ? `指示: ${brief.instruction}` : "指示: より明確で印象に残る文言に磨く",
      ]
        .filter(Boolean)
        .join("\n"),
      4000,
    );
    if (!result.text?.trim()) throw new Error("no text in response");
    return Response.json({ text: result.text });
  } catch (e) {
    console.error("rewrite failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "rewrite failed" },
      { status: 502 },
    );
  }
}
