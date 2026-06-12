import { promises as fs } from "fs";
import path from "path";
import { normalizeDeck } from "@/lib/normalize";
import { findChrome, renderDeckPdf } from "@/lib/exportPdf";
import { uid } from "@/lib/types";

export const maxDuration = 120;

// サーバーサイドPDF書き出し。デッキJSONを一時保存し、ヘッドレスChromeが
// /print?deck=<id> を開いて取得できるようにしてから page.pdf() する。

const EXPORT_DIR = path.join(process.cwd(), ".assets");

export async function GET() {
  return Response.json({ available: !!findChrome() });
}

export async function POST(req: Request) {
  let deck;
  try {
    const body = (await req.json()) as { deck?: unknown };
    deck = normalizeDeck(body.deck);
    if (deck.slides.length === 0) throw new Error("empty deck");
  } catch {
    return Response.json({ error: "invalid deck" }, { status: 400 });
  }

  const id = uid();
  const file = path.join(EXPORT_DIR, `export-${id}.json`);
  try {
    await fs.mkdir(EXPORT_DIR, { recursive: true });
    await fs.writeFile(file, JSON.stringify(deck));
    const origin = new URL(req.url).origin;
    const pdf = await renderDeckPdf(origin, id, deck);
    const filename = encodeURIComponent(`${deck.title || "deck"}.pdf`);
    return new Response(new Uint8Array(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename*=UTF-8''${filename}`,
      },
    });
  } catch (e) {
    console.error("pdf export failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "pdf export failed" },
      { status: 503 },
    );
  } finally {
    await fs.unlink(file).catch(() => {});
  }
}
