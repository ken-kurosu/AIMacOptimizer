import { promises as fs } from "fs";
import path from "path";
import { DeckPlan, generateDeckFromPlan, generateImage2Deck } from "@/lib/image2Pipeline";
import { critiqueAndFixDeck } from "@/lib/critique";
import { generateMockDeck } from "@/lib/mock";
import { openaiAvailable, pickTextModel } from "@/lib/openai";
import { uid } from "@/lib/types";

export const maxDuration = 600;

// 外部連携用(Slackエージェント等): デッキを生成してサーバーに保存し、
// 編集画面を開くURLを返す。エディタは /?deck=<id> で開くと取り込む。
//
// 推奨フロー(構成レビューを挟む):
//   1. POST /api/generate/plan {"topic":"...","pages":5} → { plan }
//   2. plan(ページ毎の内容・モチーフ・配色)をユーザーに見せてOK/修正をもらう
//      (修正は feedback + previousPlan を付けて 1. を再実行)
//   3. POST /api/decks {"plan": <承認済みplan>} → { editUrl } をユーザーへ
// topic だけを渡せばレビューなしの一発生成も可能。

const DECKS_DIR = path.join(process.cwd(), ".assets");

interface DeckBrief {
  topic?: string;
  pages?: number;
  audience?: string;
  tone?: string;
  notes?: string;
  references?: string[];
  plan?: DeckPlan; // 承認済みの構成案
}

export async function POST(req: Request) {
  let brief: DeckBrief;
  try {
    brief = (await req.json()) as DeckBrief;
    if (!brief.topic?.trim() && !brief.plan?.pages?.length) throw new Error("no topic/plan");
  } catch {
    return Response.json({ error: "topic か plan が必要です" }, { status: 400 });
  }
  const pages = Math.max(3, Math.min(brief.pages || brief.plan?.pages?.length || 6, 12));
  const origin = new URL(req.url).origin;

  try {
    let deck;
    if (openaiAvailable()) {
      deck = brief.plan?.pages?.length
        ? await generateDeckFromPlan(brief.plan, pages)
        : await generateImage2Deck({ ...brief, topic: brief.topic!, pages });
      try {
        await critiqueAndFixDeck(origin, deck, await pickTextModel());
      } catch (e) {
        console.warn("critique loop skipped:", e instanceof Error ? e.message : e);
      }
    } else {
      deck = generateMockDeck({ topic: brief.topic || brief.plan?.title || "資料", pages });
    }

    const id = uid();
    await fs.mkdir(DECKS_DIR, { recursive: true });
    await fs.writeFile(path.join(DECKS_DIR, `deck-${id}.json`), JSON.stringify(deck));
    return Response.json({
      id,
      editUrl: `${origin}/?deck=${id}`,
      title: deck.title,
      pages: deck.slides.length,
    });
  } catch (e) {
    console.error("deck creation failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "deck creation failed" },
      { status: 502 },
    );
  }
}
