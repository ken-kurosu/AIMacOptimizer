import { DeckPlan, makeDeckPlan } from "@/lib/image2Pipeline";
import { openaiAvailable, pickTextModel, researchTopic } from "@/lib/openai";

export const maxDuration = 120;

// 構成案の作成(レビュー用)。生成前にユーザー/エージェントへ
// 「どんなデザインで・各ページに何を載せるか」を見せるための工程。
// feedback + previousPlan を渡すと修正版を返す。

interface PlanBrief {
  topic?: string;
  pages?: number;
  audience?: string;
  tone?: string;
  notes?: string;
  references?: string[];
  feedback?: string;
  previousPlan?: DeckPlan;
  research?: boolean; // Web検索で事実を集めてから構成する
  researchNotes?: string; // 取得済みの調査結果(作り直し時に再検索しないため)
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY が未設定です" }, { status: 400 });
  }
  let brief: PlanBrief;
  try {
    brief = (await req.json()) as PlanBrief;
    if (!brief.topic?.trim()) throw new Error("no topic");
  } catch {
    return Response.json({ error: "topic が必要です" }, { status: 400 });
  }
  try {
    const textModel = await pickTextModel();

    // Webリサーチ(任意)。失敗しても構成案の作成は続行する
    let researchNotes = brief.researchNotes?.trim() || undefined;
    let sources: { url: string; title?: string }[] = [];
    if (brief.research && !researchNotes) {
      try {
        const r = await researchTopic(textModel, brief.topic!);
        researchNotes = r.summary;
        sources = r.sources;
      } catch (e) {
        console.warn("research skipped:", e instanceof Error ? e.message : e);
      }
    }
    const notes = [
      brief.notes,
      researchNotes
        ? `Web調査で確認できた事実(正確に反映する。ここに無い数値を使う場合は「仮」と明記):\n${researchNotes}`
        : "",
    ]
      .filter(Boolean)
      .join("\n\n");

    const plan = await makeDeckPlan(
      { topic: brief.topic!, pages: brief.pages || 6, audience: brief.audience, tone: brief.tone, notes: notes || undefined, references: brief.references },
      brief.feedback,
      brief.previousPlan,
    );
    return Response.json({ plan, model: textModel, sources, researchNotes });
  } catch (e) {
    console.error("plan failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "plan failed" },
      { status: 502 },
    );
  }
}
