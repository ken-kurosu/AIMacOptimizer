// 構造化紙面(見出し帯/本文ゾーン/結論帯)の決定的レイアウト検証。
// APIを呼ばずに、参考資料風の典型ページで重なり・はみ出しがないことを確認する。
//   npx tsx scripts/verify-structure.ts
import { BAND, clampBodyZone, takeawayElements, typesetHeader, typesetZone, zoneForSpace } from "../lib/image2Pipeline";

let failed = 0;
const check = (name: string, ok: boolean, detail = "") => {
  console.log(`${ok ? "✓" : "✗"} ${name}${detail ? `  (${detail})` : ""}`);
  if (!ok) failed++;
};

const cases = [
  {
    name: "ボトルネック分析(番号ステップ4つ)",
    header: [
      { role: "kicker", text: "SALES FUNNEL" },
      { role: "title", text: "2. 現行営業導線のボトルネック" },
    ],
    body: [
      { role: "body", text: "① リスト追加・架電・メール" },
      { role: "body", text: "② 無料露出提案(メディア掲載・バナー掲載)" },
      { role: "body", text: "③ 初回商談" },
      { role: "body", text: "④ 360万円の番傘広告提案" },
    ],
    takeaway: "現行導線では、入口オファーと本命商材の間にギャップがある",
    space: "left",
  },
  {
    name: "長いタイトル+要点3つ",
    header: [
      { role: "kicker", text: "BACKEND PRODUCT" },
      { role: "title", text: "5. 継続されるサブスクリプションの条件を満たす設計" },
    ],
    body: [
      { role: "body", text: "・1ストップ解決" },
      { role: "body", text: "・2ライフ習慣化" },
      { role: "body", text: "・3コミュニティ帰属" },
    ],
    takeaway: "「毎月聞ける安心」を売ると、解約理由が消える",
    space: "right",
  },
];

for (const c of cases) {
  console.log(`\n== ${c.name}`);
  const header = typesetHeader(c.header);
  const headerBottom = Math.max(...header.map((p) => p.y + p.h));
  check("見出しが上部に収まる", headerBottom <= 180, `bottom=${headerBottom}`);

  // ビジョンが帯に被る大きなゾーンを返したと仮定してもクランプされる
  const wild = { x: 80, y: 60, w: 700, h: 640 };
  const zone = clampBodyZone(wild, headerBottom + 28, BAND.y - 20);
  check("本文ゾーンが中段に収まる", zone.y >= headerBottom + 28 && zone.y + zone.h <= BAND.y - 20, JSON.stringify(zone));

  const body = typesetZone(c.body, zone);
  const bodyBottom = Math.max(...body.map((p) => p.y + p.h));
  check("本文が結論帯に被らない", bodyBottom <= BAND.y, `bottom=${bodyBottom} band.y=${BAND.y}`);
  check("本文が見出しに被らない", Math.min(...body.map((p) => p.y)) >= headerBottom, "");

  const els = takeawayElements(c.takeaway);
  const band = els[0];
  const label = els[1];
  check("結論帯が最下部・スライド内", band.y + band.h <= 720 - 24 && band.y >= 620, `y=${band.y}`);
  check(
    "結論テキストが帯の内側",
    label.type === "text" &&
      label.y >= band.y &&
      label.y + label.h <= band.y + band.h &&
      label.fontSize >= 13,
    label.type === "text" ? `font=${label.fontSize}px h=${label.h}` : "",
  );

  // フォールバックゾーン(ビジョン失敗時)でも同様
  const fb = clampBodyZone(zoneForSpace(c.space), headerBottom + 28, BAND.y - 20);
  const fbBottom = Math.max(...typesetZone(c.body, fb).map((p) => p.y + p.h));
  check("フォールバックでも帯に被らない", fbBottom <= BAND.y, `bottom=${fbBottom}`);
}

console.log(failed === 0 ? "\nすべて合格" : `\n${failed}件失敗`);
process.exit(failed === 0 ? 0 : 1);
