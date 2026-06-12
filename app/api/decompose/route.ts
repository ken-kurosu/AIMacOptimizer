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

// 160x90のグリッドでアルファを見て、近接するかたまり同士をまとめながら
// 連結成分に分ける(1セル≈8px。1セルの膨張で約16-24pxの隙間まで同一パーツ扱い)。
// 細かすぎる成分は除き、大きい順に最大6パーツ返す。
const GRID_W = 160;
const GRID_H = 90;

function findComponents(rgba: Buffer): { x: number; y: number; w: number; h: number }[] {
  const cellW = SLIDE_W / GRID_W;
  const cellH = SLIDE_H / GRID_H;
  const grid = new Uint8Array(GRID_W * GRID_H);
  for (let gy = 0; gy < GRID_H; gy++) {
    for (let gx = 0; gx < GRID_W; gx++) {
      outer: for (let y = Math.floor(gy * cellH); y < Math.floor((gy + 1) * cellH); y += 2) {
        for (let x = Math.floor(gx * cellW); x < Math.floor((gx + 1) * cellW); x += 2) {
          if (rgba[(y * SLIDE_W + x) * 4 + 3] > 24) {
            grid[gy * GRID_W + gx] = 1;
            break outer;
          }
        }
      }
    }
  }
  // 1セル膨張(近接かたまりの結合)
  const dilated = new Uint8Array(grid);
  for (let gy = 0; gy < GRID_H; gy++) {
    for (let gx = 0; gx < GRID_W; gx++) {
      if (!grid[gy * GRID_W + gx]) continue;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = gx + dx;
          const ny = gy + dy;
          if (nx >= 0 && nx < GRID_W && ny >= 0 && ny < GRID_H) dilated[ny * GRID_W + nx] = 1;
        }
      }
    }
  }
  // BFSで連結成分のバウンディングボックス(元グリッド基準)を取る
  const seen = new Uint8Array(GRID_W * GRID_H);
  const comps: { x0: number; y0: number; x1: number; y1: number; cells: number }[] = [];
  for (let start = 0; start < dilated.length; start++) {
    if (!dilated[start] || seen[start]) continue;
    const queue = [start];
    seen[start] = 1;
    let x0 = GRID_W, y0 = GRID_H, x1 = -1, y1 = -1, cells = 0;
    while (queue.length) {
      const cur = queue.pop()!;
      const cx = cur % GRID_W;
      const cy = (cur / GRID_W) | 0;
      if (grid[cur]) {
        cells++;
        if (cx < x0) x0 = cx;
        if (cx > x1) x1 = cx;
        if (cy < y0) y0 = cy;
        if (cy > y1) y1 = cy;
      }
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = cx + dx;
          const ny = cy + dy;
          const ni = ny * GRID_W + nx;
          if (nx >= 0 && nx < GRID_W && ny >= 0 && ny < GRID_H && dilated[ni] && !seen[ni]) {
            seen[ni] = 1;
            queue.push(ni);
          }
        }
      }
    }
    if (x1 >= 0 && cells >= 6) comps.push({ x0, y0, x1, y1, cells }); // ノイズ除去
  }
  comps.sort((a, b) => b.cells - a.cells);
  const pad = 6;
  return comps.slice(0, 6).map((c) => {
    const x = Math.max(0, Math.floor(c.x0 * cellW) - pad);
    const y = Math.max(0, Math.floor(c.y0 * cellH) - pad);
    const x2 = Math.min(SLIDE_W, Math.ceil((c.x1 + 1) * cellW) + pad);
    const y2 = Math.min(SLIDE_H, Math.ceil((c.y1 + 1) * cellH) + pad);
    return { x, y, w: x2 - x, h: y2 - y };
  });
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY is not configured" }, { status: 400 });
  }
  let src: string;
  try {
    src = ((await req.json()) as { src?: string }).src ?? "";
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }
  const assetId = src.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
  if (!assetId) {
    return Response.json({ error: "only generated backgrounds (/api/assets/...) can be decomposed" }, { status: 400 });
  }
  const image = await readAsset(assetId);
  if (!image) return Response.json({ error: "background image not found" }, { status: 404 });

  try {
    const models = await pickTransparentImageModels();
    if (models.length === 0) {
      return Response.json({ error: "no transparency-capable image edit model is available for this API key" }, { status: 400 });
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

    // アルファの連結成分解析で、モチーフを独立した複数パーツに分割する
    const { data } = await sharp(motifPng).raw().toBuffer({ resolveWithObject: true });
    const boxes = findComponents(data);
    if (boxes.length === 0) {
      return Response.json({ error: "could not detect any motif" }, { status: 422 });
    }
    const motifs = await Promise.all(
      boxes.map(async (b) => {
        const cut = await sharp(motifPng)
          .extract({ left: b.x, top: b.y, width: b.w, height: b.h })
          .png()
          .toBuffer();
        const url = await saveAsset(`cut-${uid()}`, cut);
        return { url, x: b.x, y: b.y, w: b.w, h: b.h };
      }),
    );

    const background = await saveAsset(`bg-${uid()}`, cleanPng);
    return Response.json({ background, motifs });
  } catch (e) {
    console.error("decompose failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "decompose failed" },
      { status: 502 },
    );
  }
}
