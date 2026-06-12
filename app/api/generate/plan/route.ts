import { DeckPlan, makeDeckPlan } from "@/lib/image2Pipeline";
import { openaiAvailable, pickTextModel } from "@/lib/openai";

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
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY is not configured" }, { status: 400 });
  }
  let brief: PlanBrief;
  try {
    brief = (await req.json()) as PlanBrief;
    if (!brief.topic?.trim()) throw new Error("no topic");
  } catch {
    return Response.json({ error: "topic is required" }, { status: 400 });
  }
  try {
    const plan = await makeDeckPlan(
      { topic: brief.topic!, pages: brief.pages || 6, audience: brief.audience, tone: brief.tone, notes: brief.notes, references: brief.references },
      brief.feedback,
      brief.previousPlan,
    );
    return Response.json({ plan, model: await pickTextModel() });
  } catch (e) {
    console.error("plan failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "plan failed" },
      { status: 502 },
    );
  }
}
