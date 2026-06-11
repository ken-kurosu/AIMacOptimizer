import sharp from "sharp";
import { readAsset, saveAsset } from "@/lib/assets";
import { SLIDE_H, SLIDE_W, uid } from "@/lib/types";
import { editImage, openaiAvailable, pickTransparentImageModels } from "@/lib/openai";

export const maxDuration = 180;

// 背景の分解: 生成済み背景(1280x720アセット)を gpt-image の edits で
// 「モチーフだけの透過PNG」と「モチーフを消した無地背景」に分け、
// 透過画像のアルファ領域からモチーフの位置を実測して返す。
// クライアントは背景を差し替え、モチーフを動かせる画像要素として置き直す。

const MOTIF_PROMPT =
  "Keep ONLY the decorative motif / illustration shapes exactly as they are, in their exact original positions. " +
  "Remove the plain background wash completely. Fully transparent background. " +
  "Do not move, resize or restyle anything. ABSOLUTELY NO text, letters or numbers.";

const CLEAN_PROMPT =
  "Remove ALL decorative motifs, shapes, illustrations and objects. Keep only the plain empty background " +
  "(base color wash / gradient / paper texture), filling removed areas seamlessly with the surrounding background. " +
  "ABSOLUTELY NO text, letters or numbers.";

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY が未設定です" }, { status: 400 });
  }
  let src: string;
  try {
    src = ((await req.json()) as { src?: string }).src ?? "";
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }
  const assetId = src.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
  if (!assetId) {
    return Response.json({ error: "AI生成した背景(/api/assets/...)のみ分解できます" }, { status: 400 });
  }
  const image = await readAsset(assetId);
  if (!image) return Response.json({ error: "背景画像が見つかりません" }, { status: 404 });

  try {
    const models = await pickTransparentImageModels();
    if (models.length === 0) {
      return Response.json({ error: "透過対応の画像編集モデルが使えません" }, { status: 400 });
    }
    const model = models[0];
    const [motifRaw, cleanRaw] = await Promise.all([
      editImage(model, image, MOTIF_PROMPT, { background: "transparent" }),
      editImage(model, image, CLEAN_PROMPT, {}),
    ]);

    // editsの出力は3:2(1536x1024)に引き伸ばされるため、1280x720へ戻す(実測で確認済み)
    const motifPng = await sharp(motifRaw)
      .resize(SLIDE_W, SLIDE_H, { fit: "fill" })
      .ensureAlpha()
      .png()
      .toBuffer();
    const cleanPng = await sharp(cleanRaw).resize(SLIDE_W, SLIDE_H, { fit: "fill" }).png().toBuffer();

    // アルファ領域からモチーフのバウンディングボックスを実測
    const { data } = await sharp(motifPng).raw().toBuffer({ resolveWithObject: true });
    let x0 = SLIDE_W, y0 = SLIDE_H, x1 = -1, y1 = -1;
    for (let y = 0; y < SLIDE_H; y++) {
      for (let x = 0; x < SLIDE_W; x++) {
        if (data[(y * SLIDE_W + x) * 4 + 3] > 24) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) {
      return Response.json({ error: "モチーフを検出できませんでした" }, { status: 422 });
    }
    const pad = 4;
    x0 = Math.max(0, x0 - pad);
    y0 = Math.max(0, y0 - pad);
    x1 = Math.min(SLIDE_W - 1, x1 + pad);
    y1 = Math.min(SLIDE_H - 1, y1 + pad);
    const w = x1 - x0 + 1;
    const h = y1 - y0 + 1;
    const motifCut = await sharp(motifPng).extract({ left: x0, top: y0, width: w, height: h }).png().toBuffer();

    const background = await saveAsset(`bg-${uid()}`, cleanPng);
    const motifUrl = await saveAsset(`cut-${uid()}`, motifCut);
    return Response.json({ background, motif: { url: motifUrl, x: x0, y: y0, w, h } });
  } catch (e) {
    console.error("decompose failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "decompose failed" },
      { status: 502 },
    );
  }
}
