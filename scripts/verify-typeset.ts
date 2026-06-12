// typesetZone の決定的検証(APIキー不要)。
// 実行: npx tsx scripts/verify-typeset.ts

import { DEFAULT_ZONE, sanitizeZone, typesetZone, zoneForSpace } from "../lib/image2Pipeline";

const texts = [
  { role: "body", text: "毎日の定型作業をAIに任せて、考える時間を取り戻します" },
  { role: "kicker", text: "NEW SERVICE" },
  { role: "title", text: "家族の医療・健康記録を、ひとつにまとめるアプリ" },
  { role: "label", text: "※数値は社内検証時の目安です(仮)" },
  { role: "subtitle", text: "予防接種・通院履歴・服薬メモを家族でリアルタイムに共有" },
  { role: "body", text: "忙しい朝でも、受診前の確認が1分で終わるようになります" },
];

let failed = false;
const assert = (cond: boolean, label: string) => {
  console.log(`${cond ? "✅" : "❌"} ${label}`);
  if (!cond) failed = true;
};

// 1. 通常ゾーンでの組版
const zone = { x: 96, y: 100, w: 640, h: 520 };
const ps = typesetZone(texts, zone);

assert(ps.length === texts.length, "全テキストが配置される");

const byY = [...ps].sort((a, b) => a.y - b.y);
const roles = byY.map((p) => texts[p.index].role);
assert(
  roles[0] === "kicker" && roles[1] === "title" && roles[2] === "subtitle",
  `kicker→title→subtitle の順で組まれる (実際: ${roles.join(",")})`,
);
assert(roles[roles.length - 1] === "label", "label(注釈)が最後に来る");

let overlap = false;
for (let i = 1; i < byY.length; i++) {
  if (byY[i].y < byY[i - 1].y + byY[i - 1].h) overlap = true;
}
assert(!overlap, "要素同士が重ならない");
assert(
  ps.every((p) => p.x >= zone.x && p.x + p.w <= zone.x + zone.w + 1),
  "全要素がゾーンの横幅に収まる",
);
assert(
  byY[byY.length - 1].y + byY[byY.length - 1].h <= zone.y + zone.h + 40,
  "ゾーン高さに(ほぼ)収まる",
);

const title = ps.find((p) => texts[p.index].role === "title")!;
const body = ps.find((p) => texts[p.index].role === "body")!;
assert(title.fontSizePx >= body.fontSizePx * 2, `ジャンプ率が確保される (title ${title.fontSizePx}px / body ${body.fontSizePx}px)`);
assert(ps.every((p) => p.align === "left"), "左寄せゾーンでは左揃え");

// 2. 狭いゾーンでは全体が縮小される
const small = typesetZone(texts, { x: 96, y: 100, w: 420, h: 320 });
const smallTitle = small.find((p) => texts[p.index].role === "title")!;
assert(smallTitle.fontSizePx < title.fontSizePx, `狭いゾーンでは縮小される (${title.fontSizePx}→${smallTitle.fontSizePx}px)`);

// 3. 中央ゾーンでは中央揃え
const center = typesetZone(texts, { x: 300, y: 100, w: 680, h: 520 });
assert(center.every((p) => p.align === "center"), "中央の広いゾーンでは中央揃え");

// 4. sanitizeZone が壊れた入力を弾く/丸める
assert(sanitizeZone(undefined) === null, "zone未返却はnull");
assert(sanitizeZone({ x: "a", y: 0, w: 100, h: 100 }) === null, "非数値はnull");
const clamped = sanitizeZone({ x: -50, y: 10, w: 5000, h: 5000 })!;
assert(
  clamped.x >= 32 && clamped.x + clamped.w <= 1280 - 32 && clamped.y + clamped.h <= 720 - 32,
  "画面外の指定はスライド内に丸められる",
);
assert(DEFAULT_ZONE.w >= 360, "既定ゾーンが妥当");

// 5. space別フォールバックゾーンが全てスライド内に収まる
for (const s of ["left", "right", "top", "bottom", "center", undefined]) {
  const z = zoneForSpace(s);
  assert(
    z.x >= 32 && z.y >= 32 && z.x + z.w <= 1280 - 32 && z.y + z.h <= 720 - 20 && z.w >= 360 && z.h >= 240,
    `zoneForSpace(${s ?? "未指定"}) がスライド内の妥当な領域`,
  );
}
// rightゾーンでは右カラムに左揃えで組まれる(中央揃え誤判定しない)
const right = typesetZone(texts, zoneForSpace("right"));
assert(right.every((p) => p.x >= 624), "rightゾーンは右カラムに組まれる");

// 6. タイトルのみなしご行回避: 「…してい/る」と1文字落ちするテキストでサイズが1段下がる
const orphanTexts = [{ role: "title", text: "情報と会話がチーム間で分断している" }];
const op = typesetZone(orphanTexts, { x: 96, y: 100, w: 590, h: 520 })[0];
const emPerLine = (s: number) => 590 / s;
const em = orphanTexts[0].text.length * 1.05;
const remAt = (s: number) => em % emPerLine(s);
assert(
  !(remAt(op.fontSizePx) > 0 && remAt(op.fontSizePx) <= 1.2 && em > emPerLine(op.fontSizePx)),
  `タイトルの最終行が1文字にならないサイズが選ばれる (fs=${op.fontSizePx})`,
);

process.exit(failed ? 1 : 0);
