import { importPdfDeck } from "@/lib/importPdf";
import { openaiAvailable } from "@/lib/openai";

export const maxDuration = 600;

// 画像だけのPDF資料を編集可能なデッキへ分解する
const MAX_BYTES = 40 * 1024 * 1024;

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "PDF import requires OPENAI_API_KEY" }, { status: 400 });
  }
  const buf = Buffer.from(await req.arrayBuffer());
  if (buf.length === 0) return Response.json({ error: "empty body" }, { status: 400 });
  if (buf.length > MAX_BYTES) {
    return Response.json({ error: "PDF too large (max 40MB)" }, { status: 413 });
  }
  if (!buf.subarray(0, 5).toString("latin1").startsWith("%PDF-")) {
    return Response.json({ error: "not a PDF file" }, { status: 400 });
  }
  try {
    const deck = await importPdfDeck(buf);
    return Response.json({ deck });
  } catch (e) {
    console.error("pdf import failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "pdf import failed" },
      { status: 502 },
    );
  }
}
