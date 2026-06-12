import sharp from "sharp";
import { readAsset, saveAsset } from "@/lib/assets";
import { SLIDE_H, SLIDE_W, uid } from "@/lib/types";
import { chatJSON, editImage, openaiAvailable, pickTextModel, pickTransparentImageModels } from "@/lib/openai";

export const maxDuration = 300;

// 背景の分解(Magic Layers方式)。
//  1. gpt-image edits 1回: 背景地だけを消した「全モチーフの透過版」を作る
//     (この一括抽出は位置忠実なことを実測で確認済み)
//  2. そのアルファを「元画像の画素」に適用する → 色・位置のズレが原理的にゼロ
//  3. アルファの細かい連結成分を、ビジョンモデルの意味単位の列挙(名前+bbox+深度)で
//     グルーピングし、オブジェクトごとの透過レイヤーに切り出す
//  4. 背景はオブジェクトを消した無地版をインペインティングで作る
// ビジョン列挙に失敗した場合は連結成分そのままでレイヤー化する。

const ENUMERATE_SYSTEM = `あなたはデザインのレイヤー解析エンジンです。スライド背景画像(1280x720)を読み、描かれている視覚オブジェクトを意味単位で列挙してJSONで返します。

出力(JSONのみ): { "objects": [ { "name": "(短い表示名)", "bbox": { "x": 0-1280, "y": 0-720, "w": px, "h": px }, "depth": 0 } ] }

ルール:
- ひとまとまりとして動かしたい最小単位で分ける(例: 円の中の豆=1つ、左下の植物=1つ、波の帯=1つ)
- オブジェクト同士を重複させない。「グループ」と「その構成要素」を両方挙げない(構成要素を優先)
- 最大10個。視覚的に重要な順に。微細な点・粒・テクスチャは含めない
- depth: 0=最背面(大きな帯・グラデーション)、数字が大きいほど前面の小物
- bboxはそのオブジェクトが占める領域(正確に)
- nameは依頼された言語で短く(例: 「コーヒー豆の円」/ "coffee bean circle")`;

interface LayerObject {
  name?: string;
  bbox?: { x?: number; y?: number; w?: number; h?: number };
  depth?: number;
}

const MOTIF_PROMPT =
  "Keep ONLY the decorative motif / illustration shapes exactly as they are, in their exact original positions. " +
  "Remove the plain background wash completely. Fully transparent background. " +
  "Do not move, resize or restyle anything. ABSOLUTELY NO text, letters or numbers.";

const CLEAN_PROMPT =
  "Remove ALL decorative motifs, shapes, illustrations and objects. Keep only the plain empty background " +
  "(base color wash / gradient / paper texture), filling removed areas seamlessly with the surrounding background. " +
  "ABSOLUTELY NO text, letters or numbers.";

// 細かい連結成分解析(256x144グリッド)。レイヤー分解の素材になるため
// 旧方式(160x90+強い結合)より細かく拾い、結合は1セル(約10px)に留める
const GRID_W = 256;
const GRID_H = 144;

interface Component {
  cells: number[]; // グリッドインデックス
  x: number;
  y: number;
  w: number;
  h: number;
  size: number;
}

function findComponentsFine(rgba: Buffer): Component[] {
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
  const seen = new Uint8Array(GRID_W * GRID_H);
  const comps: Component[] = [];
  for (let start = 0; start < dilated.length; start++) {
    if (!dilated[start] || seen[start]) continue;
    const queue = [start];
    seen[start] = 1;
    const cells: number[] = [];
    let x0 = GRID_W, y0 = GRID_H, x1 = -1, y1 = -1;
    while (queue.length) {
      const cur = queue.pop()!;
      const cx = cur % GRID_W;
      const cy = (cur / GRID_W) | 0;
      if (grid[cur]) {
        cells.push(cur);
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
    if (x1 >= 0 && cells.length >= 3) {
      comps.push({
        cells,
        x: Math.floor(x0 * cellW),
        y: Math.floor(y0 * cellH),
        w: Math.ceil((x1 - x0 + 1) * cellW),
        h: Math.ceil((y1 - y0 + 1) * cellH),
        size: cells.length,
      });
    }
  }
  return comps;
}

// セル単位の割り当て。各セルを「中心を含む最小のbboxのオブジェクト」に帰属させる
// (特定性優先)。どのbboxにも入らないセルは最も近いbbox(120px以内)へ。
// 1つの連結成分が複数オブジェクトを物理的に繋いでいても(例: 点線の軌道が
// 円群を貫通)、ここで意味単位に切り分けられる。
function assignCellsToObjects(
  comps: Component[],
  objects: LayerObject[],
): { groups: Map<number, Component>; leftover: Component | null } {
  const cellW = SLIDE_W / GRID_W;
  const cellH = SLIDE_H / GRID_H;
  const boxes = objects.map((o) => ({
    x: o.bbox?.x ?? 0,
    y: o.bbox?.y ?? 0,
    w: o.bbox?.w ?? 0,
    h: o.bbox?.h ?? 0,
  }));
  const cellsByObj = new Map<number, number[]>();
  const leftoverCells: number[] = [];

  for (const comp of comps) {
    for (const cell of comp.cells) {
      const px = ((cell % GRID_W) + 0.5) * cellW;
      const py = (((cell / GRID_W) | 0) + 0.5) * cellH;
      let best = -1;
      let bestArea = Infinity;
      for (let i = 0; i < boxes.length; i++) {
        const b = boxes[i];
        if (b.w <= 0 || b.h <= 0) continue;
        if (px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h) {
          const area = b.w * b.h;
          if (area < bestArea) {
            bestArea = area;
            best = i;
          }
        }
      }
      if (best < 0) {
        // どのbboxにも入らない → 最近傍(120px以内)
        let bestDist = 120;
        for (let i = 0; i < boxes.length; i++) {
          const b = boxes[i];
          if (b.w <= 0 || b.h <= 0) continue;
          const dx = Math.max(b.x - px, 0, px - (b.x + b.w));
          const dy = Math.max(b.y - py, 0, py - (b.y + b.h));
          const d = Math.hypot(dx, dy);
          if (d < bestDist) {
            bestDist = d;
            best = i;
          }
        }
      }
      if (best >= 0) {
        if (!cellsByObj.has(best)) cellsByObj.set(best, []);
        cellsByObj.get(best)!.push(cell);
      } else {
        leftoverCells.push(cell);
      }
    }
  }

  const toComponent = (cells: number[]): Component => {
    let x0 = GRID_W, y0 = GRID_H, x1 = -1, y1 = -1;
    for (const cell of cells) {
      const gx = cell % GRID_W;
      const gy = (cell / GRID_W) | 0;
      if (gx < x0) x0 = gx;
      if (gx > x1) x1 = gx;
      if (gy < y0) y0 = gy;
      if (gy > y1) y1 = gy;
    }
    return {
      cells,
      x: Math.floor(x0 * cellW),
      y: Math.floor(y0 * cellH),
      w: Math.ceil((x1 - x0 + 1) * cellW),
      h: Math.ceil((y1 - y0 + 1) * cellH),
      size: cells.length,
    };
  };

  const groups = new Map<number, Component>();
  for (const [i, cells] of cellsByObj) {
    if (cells.length >= 3) groups.set(i, toComponent(cells));
  }
  return { groups, leftover: leftoverCells.length >= 12 ? toComponent(leftoverCells) : null };
}

// 成分セル群からレイヤーを切り出す(画素は元画像、アルファは抽出版×セルマスク)
async function cutLayer(
  originalRgb: Buffer, // 1280x720 RGB
  motifRgba: Buffer, // 1280x720 RGBA(アルファ参照用)
  comps: Component[],
): Promise<{ png: Buffer; x: number; y: number; w: number; h: number } | null> {
  const cellW = SLIDE_W / GRID_W;
  const cellH = SLIDE_H / GRID_H;
  const cellSet = new Set<number>();
  let x0 = SLIDE_W, y0 = SLIDE_H, x1 = -1, y1 = -1;
  for (const c of comps) {
    for (const cell of c.cells) cellSet.add(cell);
    if (c.x < x0) x0 = c.x;
    if (c.y < y0) y0 = c.y;
    if (c.x + c.w > x1) x1 = c.x + c.w;
    if (c.y + c.h > y1) y1 = c.y + c.h;
  }
  if (x1 < 0) return null;
  const pad = 6;
  x0 = Math.max(0, x0 - pad);
  y0 = Math.max(0, y0 - pad);
  x1 = Math.min(SLIDE_W, x1 + pad);
  y1 = Math.min(SLIDE_H, y1 + pad);
  const w = x1 - x0;
  const h = y1 - y0;

  const out = Buffer.alloc(w * h * 4);
  let visible = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const sx = x0 + x;
      const sy = y0 + y;
      const gx = (sx / cellW) | 0;
      const gy = (sy / cellH) | 0;
      let inMask = cellSet.has(gy * GRID_W + gx);
      if (!inMask) {
        // 1セルの余裕(縁のアンチエイリアスを拾う)
        for (let dy = -1; dy <= 1 && !inMask; dy++) {
          for (let dx = -1; dx <= 1 && !inMask; dx++) {
            inMask = cellSet.has((gy + dy) * GRID_W + (gx + dx));
          }
        }
      }
      const a = inMask ? motifRgba[(sy * SLIDE_W + sx) * 4 + 3] : 0;
      const si3 = (sy * SLIDE_W + sx) * 3;
      const di = (y * w + x) * 4;
      out[di] = originalRgb[si3];
      out[di + 1] = originalRgb[si3 + 1];
      out[di + 2] = originalRgb[si3 + 2];
      out[di + 3] = a;
      if (a > 24) visible++;
    }
  }
  if (visible < 64) return null;
  const png = await sharp(out, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
  return { png, x: x0, y: y0, w, h };
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY is not configured" }, { status: 400 });
  }
  let src: string;
  let lang = "ja";
  try {
    const body = (await req.json()) as { src?: string; lang?: string };
    src = body.src ?? "";
    if (body.lang === "en") lang = "en";
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

    // 並列: モチーフ抽出 / 無地背景 / 意味単位の列挙
    const small = await sharp(image).resize(800, 450).jpeg({ quality: 80 }).toBuffer();
    const [motifRaw, cleanRaw, enumerated] = await Promise.all([
      editImage(model, image, MOTIF_PROMPT, { background: "transparent" }),
      editImage(model, image, CLEAN_PROMPT, {}),
      chatJSON<{ objects?: LayerObject[] }>(
        await pickTextModel(),
        ENUMERATE_SYSTEM,
        [
          {
            type: "image_url",
            image_url: { url: `data:image/jpeg;base64,${small.toString("base64")}`, detail: "high" },
          },
          {
            type: "text",
            text:
              lang === "en"
                ? "List the visual objects in this 1280x720 background. Names in English."
                : "この1280x720背景の視覚オブジェクトを列挙してください。nameは日本語で。",
          },
        ],
        8000,
      ).catch((e) => {
        console.warn("layer enumeration failed:", e instanceof Error ? e.message : e);
        return { objects: [] as LayerObject[] };
      }),
    ]);

    const motifPng = await sharp(motifRaw)
      .resize(SLIDE_W, SLIDE_H, { fit: "fill" })
      .ensureAlpha()
      .png()
      .toBuffer();
    const cleanPng = await sharp(cleanRaw).resize(SLIDE_W, SLIDE_H, { fit: "fill" }).png().toBuffer();

    const motifRgba = await sharp(motifPng).raw().toBuffer();
    const originalRgb = await sharp(image).removeAlpha().raw().toBuffer();
    const comps = findComponentsFine(motifRgba);
    if (comps.length === 0) {
      return Response.json({ error: "could not detect any motif" }, { status: 422 });
    }

    const objects = (enumerated.objects ?? []).slice(0, 10);
    let motifs: { url: string; x: number; y: number; w: number; h: number; name?: string; depth: number }[] = [];

    if (objects.length > 0) {
      // 意味単位グルーピング(Magic Layers方式): セル単位で最も特定的なオブジェクトへ
      const { groups, leftover } = assignCellsToObjects(comps, objects);
      const cut = await Promise.all(
        [...groups.entries()].map(async ([objIndex, group]) => {
          const layer = await cutLayer(originalRgb, motifRgba, [group]);
          if (!layer) return null;
          const o = objects[objIndex];
          const url = await saveAsset(`cut-${uid()}`, layer.png);
          return {
            url,
            x: layer.x,
            y: layer.y,
            w: layer.w,
            h: layer.h,
            name: o.name?.trim() || undefined,
            depth: o.depth ?? objIndex,
          };
        }),
      );
      motifs = cut.filter((m): m is NonNullable<typeof m> => m !== null);
      // どのオブジェクトにも帰属しなかった残り(あれば)を1レイヤーに
      if (leftover) {
        const layer = await cutLayer(originalRgb, motifRgba, [leftover]);
        if (layer) {
          const url = await saveAsset(`cut-${uid()}`, layer.png);
          motifs.push({ url, x: layer.x, y: layer.y, w: layer.w, h: layer.h, depth: 99 });
        }
      }
    }

    if (motifs.length === 0) {
      // フォールバック: 大きい成分から最大8レイヤー
      const top = [...comps].sort((a, b) => b.size - a.size).slice(0, 8);
      const cut = await Promise.all(
        top.map(async (c, i) => {
          const layer = await cutLayer(originalRgb, motifRgba, [c]);
          if (!layer) return null;
          const url = await saveAsset(`cut-${uid()}`, layer.png);
          return { url, x: layer.x, y: layer.y, w: layer.w, h: layer.h, depth: i };
        }),
      );
      motifs = cut.filter((m): m is NonNullable<typeof m> => m !== null);
    }
    if (motifs.length === 0) {
      return Response.json({ error: "could not detect any motif" }, { status: 422 });
    }

    // 背面(depth小)が先(クライアントはこの順で背面から積む)。同深度は大きい順
    motifs.sort((a, b) => a.depth - b.depth || b.w * b.h - a.w * a.h);

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
