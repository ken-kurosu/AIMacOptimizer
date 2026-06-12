import { promises as fs } from "fs";
import path from "path";
import { generateImage2Deck } from "@/lib/image2Pipeline";
import { critiqueAndFixDeck } from "@/lib/critique";
import { generateMockDeck } from "@/lib/mock";
import { openaiAvailable, pickTextModel } from "@/lib/openai";
import { uid } from "@/lib/types";

export const maxDuration = 600;

// 外部連携用(Slackエージェント等): デッキを生成してサーバーに保存し、
// 編集画面を開くURLを返す。エディタは /?deck=<id> で開くと取り込む。
//
//   curl -X POST <origin>/api/decks -H "Content-Type: application/json" \
//     -d '{"topic":"...","pages":5}'
//   → { "id": "...", "editUrl": "<origin>/?deck=...", "title": "...", "pages": 5 }

const DECKS_DIR = path.join(process.cwd(), ".assets");

interface DeckBrief {
  topic?: string;
  pages?: number;
  audience?: string;
  tone?: string;
  notes?: string;
  references?: string[];
}

export async function POST(req: Request) {
  let brief: DeckBrief;
  try {
    brief = (await req.json()) as DeckBrief;
    if (!brief.topic?.trim()) throw new Error("no topic");
  } catch {
    return Response.json({ error: "topic が必要です" }, { status: 400 });
  }
  const pages = Math.max(3, Math.min(brief.pages || 6, 12));
  const origin = new URL(req.url).origin;

  try {
    let deck;
    if (openaiAvailable()) {
      deck = await generateImage2Deck({ ...brief, topic: brief.topic!, pages });
      try {
        await critiqueAndFixDeck(origin, deck, await pickTextModel());
      } catch (e) {
        console.warn("critique loop skipped:", e instanceof Error ? e.message : e);
      }
    } else {
      deck = generateMockDeck({ topic: brief.topic!, pages });
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
