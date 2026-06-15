// テキストPDFの取り込みで、文字が元の位置・サイズ・太さのまま編集可能テキストとして
// 配置されることを検証する。最小のテキストPDFを生成して importPdfDeck にかける。
//   npx tsx scripts/verify-pdf-import.ts
import { importPdfDeck } from "../lib/importPdf";

// 1280x720のページに既知座標で2行のテキストを置いた最小PDFを組み立てる
function makeTextPdf(): Buffer {
  const objs: string[] = [];
  objs[1] = "<</Type /Catalog /Pages 2 0 R>>";
  objs[2] = "<</Type /Pages /Kids [3 0 R] /Count 1>>";
  objs[3] =
    "<</Type /Page /Parent 2 0 R /MediaBox [0 0 1280 720] /Resources <</Font <</F1 5 0 R>>>> /Contents 4 0 R>>";
  const stream =
    "BT /F1 48 Tf 100 600 Td (Hello Title) Tj ET\nBT /F1 20 Tf 100 500 Td (Body line one) Tj ET\n";
  objs[4] = "<</Length " + stream.length + ">>\nstream\n" + stream + "endstream";
  objs[5] = "<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>";
  let pdf = "%PDF-1.4\n";
  const offsets: number[] = [];
  for (let i = 1; i <= 5; i++) {
    offsets[i] = Buffer.byteLength(pdf, "latin1");
    pdf += i + " 0 obj " + objs[i] + " endobj\n";
  }
  const xrefPos = Buffer.byteLength(pdf, "latin1");
  pdf += "xref\n0 6\n0000000000 65535 f \n";
  for (let i = 1; i <= 5; i++) pdf += String(offsets[i]).padStart(10, "0") + " 00000 n \n";
  pdf += "trailer <</Size 6 /Root 1 0 R>>\nstartxref\n" + xrefPos + "\n%%EOF";
  return Buffer.from(pdf, "latin1");
}

let failed = 0;
const check = (name: string, ok: boolean, detail = "") => {
  console.log(`${ok ? "✓" : "✗"} ${name}${detail ? `  (${detail})` : ""}`);
  if (!ok) failed++;
};
const near = (a: number, b: number, tol: number) => Math.abs(a - b) <= tol;

(async () => {
  const deck = await importPdfDeck(makeTextPdf());
  check("1ページに分解される", deck.slides.length === 1, `${deck.slides.length}`);
  const els = (deck.slides[0]?.elements ?? []).filter((e) => e.type === "text");
  check("テキストが2要素(行単位)抽出される", els.length === 2, `${els.length}`);

  const title = els.find((e) => e.type === "text" && e.text.includes("Hello")) as
    | (typeof els)[number]
    | undefined;
  const body = els.find((e) => e.type === "text" && e.text.includes("Body")) as
    | (typeof els)[number]
    | undefined;

  if (title && title.type === "text") {
    check("見出し: 文字が一致", title.text === "Hello Title", title.text);
    check("見出し: 位置が元のまま", near(title.x, 100, 6) && near(title.y, 72, 10), `x=${title.x} y=${title.y}`);
    check("見出し: サイズが元のまま(48)", near(title.fontSize, 48, 4), `${title.fontSize}`);
    check("見出し: 太字を保持", title.fontWeight >= 700, `${title.fontWeight}`);
  } else check("見出しが見つかる", false);

  if (body && body.type === "text") {
    check("本文: 文字が一致", body.text === "Body line one", body.text);
    check("本文: 位置が元のまま", near(body.x, 100, 6) && near(body.y, 200, 12), `x=${body.x} y=${body.y}`);
    check("本文: サイズが元のまま(20)", near(body.fontSize, 20, 4), `${body.fontSize}`);
  } else check("本文が見つかる", false);

  // 背景画像(文字を塗り潰した版)が作られている
  check("背景画像が作られる", !!deck.slides[0]?.background.image?.startsWith("/api/assets/"));

  console.log(failed === 0 ? "\nすべて合格" : `\n${failed}件失敗`);
  process.exit(failed === 0 ? 0 : 1);
})().catch((e) => {
  console.error("FAILED:", e);
  process.exit(1);
});
