import { promises as fs } from "fs";
import path from "path";
import { DeckPlan, generateDeckFromPlan, generateImage2Deck } from "@/lib/image2Pipeline";
import { critiqueAndFixDeck } from "@/lib/critique";
import { decomposeDeckLayers } from "@/lib/decompose";
import { generateMockDeck } from "@/lib/mock";
import { normalizeDeck } from "@/lib/normalize";
import { openaiAvailable, pickTextModel, researchTopic } from "@/lib/openai";
import { Deck, uid } from "@/lib/types";

export const maxDuration = 900;

// デッキの保存・一覧と、外部連携用(Slackエージェント等)の生成API。
//
// 推奨フロー(構成レビューを挟む):
//   1. POST /api/generate/plan {"topic":"...","pages":5} → { plan }
//   2. plan(ページ毎の内容・モチーフ・配色)をユーザーに見せてOK/修正をもらう
//      (修正は feedback + previousPlan を付けて 1. を再実行)
//   3. POST /api/decks {"plan": <承認済みplan>} → { editUrl } をユーザーへ
// topic だけを渡せばレビューなしの一発生成、deck を渡せば保存のみ。

const DECKS_DIR = path.join(process.cwd(), ".assets");

interface DeckBrief {
  topic?: string;
  pages?: number;
  audience?: string;
  tone?: string;
  notes?: string;
  references?: string[];
  plan?: DeckPlan; // 承認済みの構成案から生成
  deck?: unknown; // 既存デッキの保存のみ(共有リンク作成)
  research?: boolean; // topicからの一発生成時にWeb検索で事実を集める
  title?: string;
  lang?: string; // レイヤー名などの言語(ja/en)
}

function editUrlFor(origin: string, id: string): string {
  const token = process.env.SLIDE_STUDIO_API_TOKEN;
  return `${origin}/?deck=${id}${token ? `&token=${encodeURIComponent(token)}` : ""}`;
}

async function saveDeck(deck: Deck): Promise<string> {
  const id = uid();
  await fs.mkdir(DECKS_DIR, { recursive: true });
  await fs.writeFile(path.join(DECKS_DIR, `deck-${id}.json`), JSON.stringify(deck));
  return id;
}

// 保存済みデッキの一覧(新しい順)
export async function GET() {
  try {
    const files = await fs.readdir(DECKS_DIR).catch(() => [] as string[]);
    const decks = await Promise.all(
      files
        .filter((f) => /^deck-[a-z0-9]+\.json$/.test(f))
        .map(async (f) => {
          const p = path.join(DECKS_DIR, f);
          const [stat, raw] = await Promise.all([fs.stat(p), fs.readFile(p, "utf8")]);
          let title = "無題のデッキ";
          let pages = 0;
          try {
            const d = JSON.parse(raw);
            title = d.title || title;
            pages = d.slides?.length ?? 0;
          } catch {}
          return { id: f.slice(5, -5), title, pages, updatedAt: stat.mtimeMs };
        }),
    );
    decks.sort((a, b) => b.updatedAt - a.updatedAt);
    return Response.json({ decks });
  } catch (e) {
    return Response.json({ error: e instanceof Error ? e.message : "list failed" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  let brief: DeckBrief;
  try {
    brief = (await req.json()) as DeckBrief;
    if (!brief.topic?.trim() && !brief.plan?.pages?.length && !brief.deck) {
      throw new Error("no input");
    }
  } catch {
    return Response.json({ error: "topic か plan か deck が必要です" }, { status: 400 });
  }
  const origin = new URL(req.url).origin;

  try {
    // 保存のみ(エディタからの共有リンク作成)
    if (brief.deck) {
      const deck = normalizeDeck(brief.deck);
      if (brief.title) deck.title = brief.title;
      const id = await saveDeck(deck);
      return Response.json({
        id,
        editUrl: editUrlFor(origin, id),
        title: deck.title,
        pages: deck.slides.length,
      });
    }

    const pages = brief.plan?.pages?.length || brief.pages || undefined;
    let deck;
    if (openaiAvailable()) {
      if (brief.research && !brief.plan?.pages?.length && brief.topic) {
        try {
          const r = await researchTopic(await pickTextModel(), brief.topic);
          brief.notes = [brief.notes, `Web調査で確認できた事実(正確に反映する):\n${r.summary}`]
            .filter(Boolean)
            .join("\n\n");
        } catch (e) {
          console.warn("research skipped:", e instanceof Error ? e.message : e);
        }
      }
      deck = brief.plan?.pages?.length
        ? await generateDeckFromPlan(brief.plan, brief.plan.pages.length)
        : await generateImage2Deck({ ...brief, topic: brief.topic!, pages });
      try {
        await critiqueAndFixDeck(origin, deck, await pickTextModel());
      } catch (e) {
        console.warn("critique loop skipped:", e instanceof Error ? e.message : e);
      }
      // 編集URLを開いた時点でレイヤーが分解済みになっているようにする
      try {
        const layered = await decomposeDeckLayers(deck, brief.lang === "en" ? "en" : "ja");
        if (layered > 0) console.log(`auto-decompose: ${layered}/${deck.slides.length} slides layered`);
      } catch (e) {
        console.warn("auto-decompose skipped:", e instanceof Error ? e.message : e);
      }
    } else {
      deck = generateMockDeck({ topic: brief.topic || brief.plan?.title || "資料", pages: pages ?? 6 });
    }

    const id = await saveDeck(deck);
    return Response.json({
      id,
      editUrl: editUrlFor(origin, id),
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

