// applyContrast の決定的検証スクリプト(APIキー不要)。
// 合成背景: 左半分=濃紺フラット / 右半分=白黒ノイズ(騒がしい領域)
//   1. 濃紺の上に濃色文字 → 白に反転され、スクリムは不要
//   2. ノイズの上の文字 → スクリムが敷かれる
//   3. 近接するノイズ上の2要素 → スクリムが1枚にマージされる
// 実行: npx tsx scripts/verify-contrast.ts

import sharp from "sharp";
import { applyContrast, Placement } from "../lib/image2Pipeline";
import { normalizeTheme } from "../lib/normalize";

async function main() {
  const W = 1280;
  const H = 720;
  const raw = Buffer.alloc(W * H * 3);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 3;
      if (x < W / 2) {
        raw[i] = 16; raw[i + 1] = 28; raw[i + 2] = 64; // 濃紺フラット
      } else {
        const v = Math.random() < 0.5 ? 30 : 230; // 高コントラストノイズ
        raw[i] = raw[i + 1] = raw[i + 2] = v;
      }
    }
  }
  const bg = await sharp(raw, { raw: { width: W, height: H, channels: 3 } }).png().toBuffer();

  const theme = normalizeTheme(undefined);
  const texts = [
    { role: "title", text: "濃紺の上の濃色タイトル" },
    { role: "body", text: "ノイズの上の本文その1" },
    { role: "body", text: "ノイズの上の本文その2" },
  ];
  const placements: Placement[] = [
    { index: 0, x: 80, y: 200, w: 480, h: 120, fontSizePx: 56, fontWeight: 900, align: "left", colorHex: "#0F172A" },
    { index: 1, x: 720, y: 200, w: 400, h: 40, fontSizePx: 18, fontWeight: 400, align: "left", colorHex: "#0F172A" },
    { index: 2, x: 720, y: 280, w: 400, h: 40, fontSizePx: 18, fontWeight: 400, align: "left", colorHex: "#0F172A" },
  ];

  const els = await applyContrast(placements, texts, bg, theme);
  const shapes = els.filter((e) => e.type === "shape");
  const txt = els.filter((e) => e.type === "text");

  const assert = (cond: boolean, label: string) => {
    console.log(`${cond ? "✅" : "❌"} ${label}`);
    if (!cond) process.exitCode = 1;
  };

  assert(txt[0].type === "text" && txt[0].color === "#FFFFFF", "濃紺上の濃色文字が白に反転される");
  assert(shapes.length === 1, `ノイズ上の2要素のスクリムが1枚にマージされる (実際: ${shapes.length}枚)`);
  const s = shapes[0];
  if (s && s.type === "shape") {
    assert(s.x <= 720 - 20 && s.x + s.w >= 1120, "スクリムが両方のテキスト範囲を覆う");
    assert(s.name === "scrim", "スクリムにname=scrimが付く");
    console.log("   scrim:", JSON.stringify({ x: s.x, y: s.y, w: s.w, h: s.h, fill: s.fill, opacity: s.opacity }));
  }
  // 濃紺側はフラットなのでスクリム対象外であること(=スクリムが左半分に出ていない)
  assert(!shapes.some((sh) => sh.x < 640 && sh.x + sh.w < 700), "フラットな濃紺側にはスクリムが敷かれない");
}

main();
