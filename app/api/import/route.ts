import { importPdfDeck } from "@/lib/importPdf";

export const maxDuration = 600;

// PDF資料を編集可能なデッキへ分解する。
// テキストレイヤーのあるPDFはOpenAIキー無しでも分解可能(画像のみPDFはビジョンを使う)。
const MAX_BYTES = 40 * 1024 * 1024;

export async function POST(req: Request) {
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
    const msg = e instanceof Error ? e.message : "pdf import failed";
    // A pdfjs structure error usually means a truncated (size limit) or corrupt PDF
    const friendly = /invalid pdf|structure|xref|startxref|corrupt/i.test(msg)
      ? "Could not read the PDF (it may be corrupt or truncated). Try a different file."
      : msg;
    return Response.json({ error: friendly }, { status: 502 });
  }
}
