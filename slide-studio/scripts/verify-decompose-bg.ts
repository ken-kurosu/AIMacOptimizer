// クリーン背景の合成保存性を検証する。
//   - レイヤーが覆う領域(成分セル+1セルの余白)はクリーン画素に
//   - それ以外は元画素をそのまま残す
// これにより「背景を消したのにレイヤーにも無い=消失」が起きないことを保証する。
//   npx tsx scripts/verify-decompose-bg.ts
import sharp from "sharp";
import { buildCleanBackground } from "../lib/decompose";
import { SLIDE_H, SLIDE_W } from "../lib/types";

const GRID_W = 256;
const GRID_H = 144;

let failed = 0;
const check = (name: string, ok: boolean, detail = "") => {
  console.log(`${ok ? "✓" : "✗"} ${name}${detail ? `  (${detail})` : ""}`);
  if (!ok) failed++;
};

async function main() {
  // 元画像=全面 赤(200,40,40)、クリーン=全面 白(255,255,255)
  const original = Buffer.alloc(SLIDE_W * SLIDE_H * 3);
  const clean = Buffer.alloc(SLIDE_W * SLIDE_H * 3);
  for (let i = 0; i < SLIDE_W * SLIDE_H; i++) {
    original[i * 3] = 200; original[i * 3 + 1] = 40; original[i * 3 + 2] = 40;
    clean[i * 3] = 255; clean[i * 3 + 1] = 255; clean[i * 3 + 2] = 255;
  }
  // 中央付近の1セル(gx=128,gy=72)だけをレイヤー化したと仮定
  const cx = 128, cy = 72;
  const comps = [{ cells: [cy * GRID_W + cx] }];

  const out = await buildCleanBackground(original, clean, comps);
  const raw = await sharp(out).removeAlpha().raw().toBuffer();
  const px = (gx: number, gy: number) => {
    const x = Math.floor((gx + 0.5) * (SLIDE_W / GRID_W));
    const y = Math.floor((gy + 0.5) * (SLIDE_H / GRID_H));
    const i = (y * SLIDE_W + x) * 3;
    return [raw[i], raw[i + 1], raw[i + 2]];
  };

  const center = px(cx, cy);
  check("レイヤー領域はクリーン(白)になる", center[0] === 255 && center[1] === 255 && center[2] === 255, center.join(","));

  // 1セル余白(隣接セル)もクリーンに含む
  const neighbor = px(cx + 1, cy);
  check("隣接1セルもクリーンに含む(縁のアンチエイリアス対策)", neighbor[0] === 255, neighbor.join(","));

  // 遠い領域は元画素(赤)を保持 = 消失しない
  const farCorner = px(5, 5);
  check("レイヤー外は元画素を保持(消失しない)", farCorner[0] === 200 && farCorner[1] === 40, farCorner.join(","));
  const farRight = px(250, 140);
  check("離れた領域も元画素を保持", farRight[0] === 200, farRight.join(","));

  console.log(failed === 0 ? "\nすべて合格" : `\n${failed}件失敗`);
  process.exit(failed === 0 ? 0 : 1);
}

main();
