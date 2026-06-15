import { importPdfDeck } from "@/lib/importPdf";

export const maxDuration = 600;

// PDF資料を編集可能なデッキへ分解する。
// テキストレイヤーのあるPDFはOpenAIキー無しでも分解可能(画像のみPDFはビジョンを使う)。
const MAX_BYTES = 40 * 1024 * 1024;

export async function POST(req: Request) {
  const buf = Buffer.from(await req.arrayBuffer());
  if (buf.length === 0) return Response.json({ error: "empty body" }, { status: 400 });
  if (buf.length > MAX_BYTES) {
    return Response.json({ error: "PDFが大きすぎます(40MBまで)" }, { status: 413 });
  }
  if (!buf.subarray(0, 5).toString("latin1").startsWith("%PDF-")) {
    return Response.json({ error: "PDFファイルではありません" }, { status: 400 });
  }
  try {
    const deck = await importPdfDeck(buf);
    return Response.json({ deck });
  } catch (e) {
    console.error("pdf import failed:", e);
    const msg = e instanceof Error ? e.message : "pdf import failed";
    // pdfjsの構造エラーは、本文の途中切れ(サイズ上限)や壊れたPDFが原因のことが多い
    const friendly = /invalid pdf|structure|xref|startxref|corrupt/i.test(msg)
      ? "PDFを読み込めませんでした(ファイルが壊れているか、途中で切れている可能性があります)。別のPDFでお試しください。"
      : msg;
    return Response.json({ error: friendly }, { status: 502 });
  }
}
