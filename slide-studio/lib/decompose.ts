import sharp from "sharp";
import { readAsset, saveAsset } from "./assets";
import { Deck, ImageEl, SLIDE_H, SLIDE_W, uid } from "./types";
import { chatJSON, editImage, pickTextModel, pickTransparentImageModels } from "./openai";
import { asyncPool } from "./pool";

// 背景の分解(Magic Layers方式)。/api/decompose と生成パイプラインの両方から使う。
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
- 【1物体=1オブジェクト・最重要】現実に1つの物体は、色や面が複数に分かれて見えても必ず1つにまとめる。例: 1棟のビルは窓・壁・影に分かれて見えても「ビル」で1つ / 1人の人物は服・髪・肌で分かれても1つ / 1台の机とPCは「デスク」で1つ。同じ物体を左右・上下・前後に割らない
- 分ける単位は「ユーザーがドラッグで個別に動かしたい現実の物体」。装飾の帯・雲・地面のような背景地と、その上の主役オブジェクトは分けてよい
- オブジェクト同士のbboxを大きく重複させない。「グループ」と「その構成要素」を両方挙げない(物体単位を優先)
- 最大10個。視覚的に重要な順に。微細な点・粒・テクスチャ・葉の1枚などは含めない(まとめる)
- depth: 0=最背面(大きな帯・グラデーション・空・地面)、数字が大きいほど前面の小物
- bboxはその物体が占める領域を過不足なく(正確に)
- nameは依頼された言語で短く、物体そのものの名前にする(例: 「オフィスビル」/ "office building")`;

interface LayerObject {
  name?: string;
  bbox?: { x?: number; y?: number; w?: number; h?: number };
  depth?: number;
}

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

function boxOf(o: LayerObject): Box {
  return { x: o.bbox?.x ?? 0, y: o.bbox?.y ?? 0, w: o.bbox?.w ?? 0, h: o.bbox?.h ?? 0 };
}

// 2つのbboxの重なり度合い = 交差面積 / 小さい方の面積(0〜1)。
// 同じ物体が2つに列挙されると、片方がもう片方をほぼ覆うので高い値になる
function overlapRatio(a: Box, b: Box): number {
  const ix = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x));
  const iy = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  const inter = ix * iy;
  const minArea = Math.max(1, Math.min(a.w * a.h, b.w * b.h));
  return inter / minArea;
}

// ビジョンが1つの物体を複数に割って列挙してしまった分を、bboxの重なりで統合する。
// 重なりが大きい(=同じ物体の別パーツ)objectをユニオンして1つにまとめる。
function mergeOverlappingObjects(objects: LayerObject[], threshold = 0.5): LayerObject[] {
  const boxes = objects.map(boxOf);
  const parent = objects.map((_, i) => i);
  const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  for (let i = 0; i < objects.length; i++) {
    for (let j = i + 1; j < objects.length; j++) {
      if (boxes[i].w <= 0 || boxes[j].w <= 0) continue;
      if (overlapRatio(boxes[i], boxes[j]) >= threshold) parent[find(i)] = find(j);
    }
  }
  const groups = new Map<number, number[]>();
  objects.forEach((_, i) => {
    const r = find(i);
    (groups.get(r) ?? groups.set(r, []).get(r)!).push(i);
  });
  const merged: LayerObject[] = [];
  for (const idxs of groups.values()) {
    if (idxs.length === 1) {
      merged.push(objects[idxs[0]]);
      continue;
    }
    // ユニオンbbox。名前は最大面積のもの、depthは最小(より背面)を採用
    const bs = idxs.map((i) => boxes[i]);
    const x = Math.min(...bs.map((b) => b.x));
    const y = Math.min(...bs.map((b) => b.y));
    const x1 = Math.max(...bs.map((b) => b.x + b.w));
    const y1 = Math.max(...bs.map((b) => b.y + b.h));
    const biggest = idxs.reduce((a, b) => (boxes[a].w * boxes[a].h >= boxes[b].w * boxes[b].h ? a : b));
    merged.push({
      name: objects[biggest].name,
      bbox: { x, y, w: x1 - x, h: y1 - y },
      depth: Math.min(...idxs.map((i) => objects[i].depth ?? i)),
    });
  }
  return merged;
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

export interface MotifLayer {
  url: string;
  x: number;
  y: number;
  w: number;
  h: number;
  name?: string;
  depth: number;
}

// 合成保存性を守るクリーン背景の合成。
// gpt-imageの「全モチーフ除去」出力(cleanRgb)を信用しすぎると、切り出しレイヤーが
// 捉えた範囲より広くモチーフを消してしまい、どのレイヤーにも残らない画素が「消失」する。
// そこで、実際にレイヤー化した成分のセル領域(+1セルの余白)だけをクリーン画素に置き換え、
// それ以外は元画素をそのまま残す。これで「背景 + 全レイヤー ≈ 元画像」が常に成り立つ。
export function buildCleanBackground(
  originalRgb: Buffer,
  cleanRgb: Buffer,
  comps: { cells: number[] }[],
): Promise<Buffer> {
  const cellW = SLIDE_W / GRID_W;
  const cellH = SLIDE_H / GRID_H;
  const cellSet = new Set<number>();
  for (const c of comps) for (const cell of c.cells) cellSet.add(cell);
  const out = Buffer.alloc(SLIDE_W * SLIDE_H * 3);
  for (let y = 0; y < SLIDE_H; y++) {
    for (let x = 0; x < SLIDE_W; x++) {
      const gx = (x / cellW) | 0;
      const gy = (y / cellH) | 0;
      let inMask = cellSet.has(gy * GRID_W + gx);
      if (!inMask) {
        for (let dy = -1; dy <= 1 && !inMask; dy++) {
          for (let dx = -1; dx <= 1 && !inMask; dx++) {
            inMask = cellSet.has((gy + dy) * GRID_W + (gx + dx));
          }
        }
      }
      const i = (y * SLIDE_W + x) * 3;
      const src = inMask ? cleanRgb : originalRgb;
      out[i] = src[i];
      out[i + 1] = src[i + 1];
      out[i + 2] = src[i + 2];
    }
  }
  return sharp(out, { raw: { width: SLIDE_W, height: SLIDE_H, channels: 3 } }).png().toBuffer();
}

export interface DecomposeResult {
  background: string; // 無地背景のアセットURL
  motifs: MotifLayer[]; // 背面(depth小)→前面の順
}

// 1枚の背景画像を「無地背景 + 透過モチーフレイヤー群」に分解する。
// 失敗(モチーフ検出なし等)は Error を投げる。
export async function decomposeBackground(image: Buffer, lang: "ja" | "en" = "ja"): Promise<DecomposeResult> {
  const models = await pickTransparentImageModels();
  if (models.length === 0) {
    throw new Error("no transparency-capable image edit model is available for this API key");
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
  if (comps.length === 0) throw new Error("could not detect any motif");

  // 1物体が複数に割れて列挙された分をbboxの重なりで統合してから割り当てる
  const objects = mergeOverlappingObjects((enumerated.objects ?? []).slice(0, 10));
  const motifs: MotifLayer[] = [];
  // 実際にレイヤー化した成分。クリーン背景のマスク(合成保存性)に使う
  const usedComps: Component[] = [];

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
          comp: group,
          motif: {
            url,
            x: layer.x,
            y: layer.y,
            w: layer.w,
            h: layer.h,
            name: o.name?.trim() || undefined,
            depth: o.depth ?? objIndex,
          },
        };
      }),
    );
    for (const r of cut) {
      if (r) {
        motifs.push(r.motif);
        usedComps.push(r.comp);
      }
    }
    // どのオブジェクトにも帰属しなかった残り(あれば)を1レイヤーに
    if (leftover) {
      const layer = await cutLayer(originalRgb, motifRgba, [leftover]);
      if (layer) {
        const url = await saveAsset(`cut-${uid()}`, layer.png);
        motifs.push({ url, x: layer.x, y: layer.y, w: layer.w, h: layer.h, depth: 99 });
        usedComps.push(leftover);
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
        return { comp: c, motif: { url, x: layer.x, y: layer.y, w: layer.w, h: layer.h, depth: i } };
      }),
    );
    for (const r of cut) {
      if (r) {
        motifs.push(r.motif);
        usedComps.push(r.comp);
      }
    }
  }
  if (motifs.length === 0) throw new Error("could not detect any motif");

  // 背面(depth小)が先(クライアントはこの順で背面から積む)。同深度は大きい順
  motifs.sort((a, b) => a.depth - b.depth || b.w * b.h - a.w * a.h);

  // 合成保存性: レイヤーが覆う領域だけをクリーン画素に、それ以外は元画素を残す。
  // これにより「背景を消したのにレイヤーにも無い=モチーフ消失」が原理的に起きない
  const cleanRgb = await sharp(cleanPng).removeAlpha().raw().toBuffer();
  const mergedBg = await buildCleanBackground(originalRgb, cleanRgb, usedComps);
  const background = await saveAsset(`bg-${uid()}`, mergedBg);
  return { background, motifs };
}

// 生成直後のデッキ全ページを自動でレイヤー分解する。
// 「ユーザーが編集を始める時点で、初めからレイヤーが分解されている」ための工程。
// 分解は見た目を変えない(合成結果≈元画像)ので、批評ループの後に安全に実行できる。
// ページ単位の失敗は許容し、そのページは一枚絵のまま残す(後から手動分解できる)。
export async function decomposeDeckLayers(deck: Deck, lang: "ja" | "en" = "ja"): Promise<number> {
  const targets = deck.slides.filter((s) => s.background.image?.startsWith("/api/assets/"));
  let done = 0;
  await asyncPool(3, targets, async (slide, i) => {
    try {
      const assetId = slide.background.image!.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
      if (!assetId) return;
      const image = await readAsset(assetId);
      if (!image) return;
      const { background, motifs } = await decomposeBackground(image, lang);
      const layers: ImageEl[] = motifs.map((m) => ({
        id: uid(),
        type: "image",
        src: m.url,
        x: m.x,
        y: m.y,
        w: m.w,
        h: m.h,
        fit: "contain",
        name: m.name || "motif",
      }));
      // 背面(配列の先頭ほど背面)にdepth順で積む。テキスト・スクリムは常に前面
      slide.background.image = background;
      slide.elements = [...layers, ...slide.elements];
      done++;
    } catch (e) {
      console.warn(`auto-decompose: slide ${i + 1} skipped:`, e instanceof Error ? e.message : e);
    }
  });
  return done;
}
