import {
  BackgroundPreset,
  Slide,
  SlideElement,
  TextEl,
  ShapeEl,
  uid,
} from "./types";

// レイアウトテンプレート: AI生成(デモモード)と手動追加の両方で使う「グリッドの骨格」。
// 要素は絶対座標を持つが、生成時はこのテンプレート経由なので崩れない。
// 配置後はユーザーが自由に動かせる(ハイブリッドレイアウト)。
//
// デザイン方針: カードの羅列を避け、エディトリアルな構成にする。
// 大きな余白・高いジャンプ率・番号+細罫線のリスト・全面塗りページ・
// 画面外にはみ出す装飾サークル(=動かせるパーツ層)を使う。

const M = 80; // 基本マージン

function text(partial: Omit<TextEl, "id" | "type">): TextEl {
  return { id: uid(), type: "text", ...partial };
}

function shape(partial: Omit<ShapeEl, "id" | "type">): ShapeEl {
  return { id: uid(), type: "shape", ...partial };
}

export function makeSlide(
  name: string,
  elements: SlideElement[],
  preset: BackgroundPreset = "none",
  color = "token:bg",
): Slide {
  return { id: uid(), name, background: { color, preset }, elements };
}

function kickerEl(label: string, x: number, y: number, color = "token:brand"): TextEl {
  return text({
    text: label,
    x,
    y,
    w: 600,
    h: 26,
    fontSize: 14,
    fontWeight: 700,
    color,
    align: "left",
    lineHeight: 1.2,
    letterSpacing: 3,
  });
}

// 表紙: 右上に画面外へはみ出す大円、左に大判タイトル
export function titleSlide(
  title: string,
  subtitle: string,
  meta: string,
  kicker = "PRESENTATION",
): Slide {
  return makeSlide("タイトル", [
    shape({
      shape: "ellipse",
      x: 850,
      y: -290,
      w: 780,
      h: 780,
      fill: "token:brandSoft",
      name: "装飾サークル",
    }),
    shape({
      shape: "ellipse",
      x: 1096,
      y: 430,
      w: 132,
      h: 132,
      fill: "token:accent",
      name: "アクセントサークル",
    }),
    kickerEl(kicker, M, 116),
    text({
      text: title,
      x: M,
      y: 196,
      w: 880,
      h: 250,
      fontSize: 72,
      fontWeight: 900,
      color: "token:ink",
      align: "left",
      lineHeight: 1.32,
      font: "heading",
    }),
    shape({ shape: "rect", x: M, y: 478, w: 64, h: 6, fill: "token:accent" }),
    text({
      text: subtitle,
      x: M,
      y: 508,
      w: 760,
      h: 64,
      fontSize: 20,
      fontWeight: 500,
      color: "token:muted",
      align: "left",
      lineHeight: 1.7,
    }),
    shape({ shape: "rect", x: M, y: 622, w: 1120, h: 1, fill: "token:line" }),
    text({
      text: meta,
      x: M,
      y: 640,
      w: 700,
      h: 26,
      fontSize: 14,
      fontWeight: 500,
      color: "token:muted",
      align: "left",
      lineHeight: 1.4,
    }),
  ]);
}

export interface AgendaItem {
  head: string;
  body: string;
  link?: string;
}

// アジェンダ: 番号+細罫線のエディトリアルなリスト。カードなし
export function agendaSlide(title: string, items: AgendaItem[], kicker = "AGENDA"): Slide {
  const els: SlideElement[] = [
    shape({
      shape: "ellipse",
      x: 1040,
      y: 480,
      w: 430,
      h: 430,
      fill: "token:brandSoft",
      name: "装飾サークル",
    }),
    kickerEl(kicker, M, 72),
    text({
      text: title,
      x: M,
      y: 104,
      w: 800,
      h: 64,
      fontSize: 40,
      fontWeight: 800,
      color: "token:ink",
      align: "left",
      lineHeight: 1.3,
      font: "heading",
    }),
  ];
  const n = Math.min(items.length, 4);
  const top = 226;
  const rowH = n <= 3 ? 132 : 110;
  items.slice(0, 4).forEach((item, i) => {
    const y = top + i * rowH;
    els.push(
      text({
        text: String(i + 1).padStart(2, "0"),
        x: M,
        y: y + 2,
        w: 90,
        h: 46,
        fontSize: 36,
        fontWeight: 800,
        color: "token:brand",
        align: "left",
        lineHeight: 1.1,
        font: "heading",
      }),
      text({
        text: item.head,
        x: 196,
        y: y,
        w: 640,
        h: 36,
        fontSize: 23,
        fontWeight: 700,
        color: "token:ink",
        align: "left",
        lineHeight: 1.35,
        link: item.link,
      }),
      text({
        text: item.body,
        x: 196,
        y: y + 40,
        w: 880,
        h: 52,
        fontSize: 15,
        fontWeight: 400,
        color: "token:muted",
        align: "left",
        lineHeight: 1.6,
      }),
      shape({ shape: "rect", x: M, y: y + rowH - 28, w: 1120, h: 1, fill: "token:line" }),
    );
  });
  return makeSlide(title, els);
}

// セクション扉: 全面ダーク塗り + 巨大なゴースト番号
export function sectionSlide(no: string, title: string): Slide {
  return makeSlide(
    `セクション ${no}`,
    [
      text({
        text: no,
        x: 540,
        y: 80,
        w: 660,
        h: 460,
        fontSize: 380,
        fontWeight: 900,
        color: "token:brand",
        align: "right",
        lineHeight: 1.1,
        font: "heading",
        opacity: 0.32,
        name: "ゴースト番号",
      }),
      kickerEl(`SECTION ${no}`, M, 296, "token:accent"),
      text({
        text: title,
        x: M,
        y: 336,
        w: 860,
        h: 120,
        fontSize: 54,
        fontWeight: 800,
        color: "#FFFFFF",
        align: "left",
        lineHeight: 1.35,
        font: "heading",
      }),
      shape({ shape: "rect", x: M, y: 478, w: 88, h: 6, fill: "token:accent" }),
    ],
    "none",
    "token:brandDark",
  );
}

// 統計: 枠なしの巨大数字 + 上の細罫線(エディトリアルなカラム)
export function statsSlide(
  title: string,
  stats: { value: string; label: string }[],
  kicker = "NUMBERS",
): Slide {
  const els: SlideElement[] = [
    shape({
      shape: "ellipse",
      x: -200,
      y: 470,
      w: 460,
      h: 460,
      fill: "token:brandSoft",
      name: "装飾サークル",
    }),
    kickerEl(kicker, M, 72),
    text({
      text: title,
      x: M,
      y: 104,
      w: 900,
      h: 64,
      fontSize: 40,
      fontWeight: 800,
      color: "token:ink",
      align: "left",
      lineHeight: 1.3,
      font: "heading",
    }),
  ];
  const n = Math.min(stats.length, 3);
  const gap = 60;
  const colW = (1280 - M * 2 - gap * (n - 1)) / n;
  stats.slice(0, 3).forEach((s, i) => {
    const x = M + i * (colW + gap);
    els.push(
      shape({ shape: "rect", x, y: 268, w: colW, h: 1, fill: "token:line" }),
      shape({ shape: "rect", x, y: 266, w: 56, h: 5, fill: "token:accent" }),
      text({
        text: s.value,
        x,
        y: 308,
        w: colW,
        h: 110,
        fontSize: 84,
        fontWeight: 900,
        color: "token:brand",
        align: "left",
        lineHeight: 1.1,
        font: "heading",
      }),
      text({
        text: s.label,
        x,
        y: 430,
        w: colW,
        h: 90,
        fontSize: 16,
        fontWeight: 500,
        color: "token:muted",
        align: "left",
        lineHeight: 1.65,
      }),
    );
  });
  return makeSlide(title, els);
}

// 引用: 全面ブランド塗り
export function quoteSlide(quote: string, author: string): Slide {
  return makeSlide(
    "メッセージ",
    [
      text({
        text: "“",
        x: 72,
        y: 56,
        w: 220,
        h: 220,
        fontSize: 210,
        fontWeight: 900,
        color: "#FFFFFF",
        align: "left",
        lineHeight: 1,
        font: "heading",
        opacity: 0.28,
      }),
      text({
        text: quote,
        x: 160,
        y: 244,
        w: 960,
        h: 230,
        fontSize: 42,
        fontWeight: 700,
        color: "#FFFFFF",
        align: "left",
        lineHeight: 1.7,
        font: "heading",
      }),
      shape({
        shape: "rect",
        x: 160,
        y: 524,
        w: 48,
        h: 2,
        fill: "#FFFFFF",
        opacity: 0.6,
      }),
      text({
        text: author,
        x: 160,
        y: 544,
        w: 800,
        h: 30,
        fontSize: 16,
        fontWeight: 500,
        color: "#FFFFFF",
        align: "left",
        lineHeight: 1.4,
        opacity: 0.75,
      }),
    ],
    "none",
    "token:brand",
  );
}

// 比較: 画面を半分に塗り分ける2分割構成。カードなし
export function twoColSlide(
  title: string,
  left: { head: string; body: string },
  right: { head: string; body: string },
  kicker = "COMPARISON",
): Slide {
  return makeSlide(title, [
    shape({
      shape: "rect",
      x: 0,
      y: 0,
      w: 600,
      h: 720,
      fill: "token:brandDark",
      name: "左パネル",
    }),
    // 左 (As-Is)
    kickerEl(kicker, M, 96, "token:accent"),
    text({
      text: left.head,
      x: M,
      y: 180,
      w: 440,
      h: 90,
      fontSize: 32,
      fontWeight: 800,
      color: "#FFFFFF",
      align: "left",
      lineHeight: 1.4,
      font: "heading",
    }),
    shape({ shape: "rect", x: M, y: 286, w: 48, h: 4, fill: "token:accent" }),
    text({
      text: left.body,
      x: M,
      y: 318,
      w: 440,
      h: 280,
      fontSize: 16.5,
      fontWeight: 400,
      color: "#FFFFFF",
      align: "left",
      lineHeight: 2,
      opacity: 0.85,
    }),
    // 右 (To-Be)
    text({
      text: title,
      x: 680,
      y: 96,
      w: 520,
      h: 30,
      fontSize: 14,
      fontWeight: 700,
      color: "token:muted",
      align: "left",
      lineHeight: 1.2,
      letterSpacing: 3,
    }),
    text({
      text: right.head,
      x: 680,
      y: 180,
      w: 520,
      h: 90,
      fontSize: 32,
      fontWeight: 800,
      color: "token:ink",
      align: "left",
      lineHeight: 1.4,
      font: "heading",
    }),
    shape({ shape: "rect", x: 680, y: 286, w: 48, h: 4, fill: "token:brand" }),
    text({
      text: right.body,
      x: 680,
      y: 318,
      w: 520,
      h: 280,
      fontSize: 16.5,
      fontWeight: 400,
      color: "token:muted",
      align: "left",
      lineHeight: 2,
    }),
  ]);
}

// コンテンツ: 左に縦タイトル列、右に番号+罫線リストの非対称構成
export function bulletsSlide(
  title: string,
  bullets: { head: string; body: string }[],
  kicker = "POINTS",
): Slide {
  const els: SlideElement[] = [
    shape({ shape: "rect", x: M, y: 112, w: 56, h: 6, fill: "token:accent" }),
    kickerEl(kicker, M, 136),
    text({
      text: title,
      x: M,
      y: 176,
      w: 330,
      h: 220,
      fontSize: 36,
      fontWeight: 800,
      color: "token:ink",
      align: "left",
      lineHeight: 1.45,
      font: "heading",
    }),
    shape({ shape: "rect", x: 470, y: 110, w: 1, h: 500, fill: "token:line" }),
  ];
  const n = Math.min(bullets.length, 4);
  const top = 116;
  const rowH = n <= 3 ? 168 : 126;
  bullets.slice(0, 4).forEach((b, i) => {
    const y = top + i * rowH;
    els.push(
      text({
        text: String(i + 1).padStart(2, "0"),
        x: 530,
        y: y,
        w: 80,
        h: 28,
        fontSize: 17,
        fontWeight: 800,
        color: "token:brand",
        align: "left",
        lineHeight: 1.2,
        letterSpacing: 1,
        font: "heading",
      }),
      text({
        text: b.head,
        x: 530,
        y: y + 32,
        w: 670,
        h: 34,
        fontSize: 22,
        fontWeight: 700,
        color: "token:ink",
        align: "left",
        lineHeight: 1.35,
      }),
      text({
        text: b.body,
        x: 530,
        y: y + 70,
        w: 670,
        h: 56,
        fontSize: 15,
        fontWeight: 400,
        color: "token:muted",
        align: "left",
        lineHeight: 1.65,
      }),
    );
    if (i < n - 1) {
      els.push(
        shape({ shape: "rect", x: 530, y: y + rowH - 26, w: 670, h: 1, fill: "token:line" }),
      );
    }
  });
  return makeSlide(title, els);
}

// クロージング: 全面ダーク + 大判メッセージ + CTAピル
export function closingSlide(title: string, sub: string, cta?: string): Slide {
  const els: SlideElement[] = [
    shape({
      shape: "ellipse",
      x: 980,
      y: -200,
      w: 560,
      h: 560,
      fill: "token:brand",
      opacity: 0.3,
      name: "装飾サークル",
    }),
    shape({
      shape: "ellipse",
      x: 1180,
      y: 540,
      w: 220,
      h: 220,
      fill: "token:accent",
      opacity: 0.5,
      name: "アクセントサークル",
    }),
    kickerEl("NEXT STEP", M, 232, "token:accent"),
    text({
      text: title,
      x: M,
      y: 282,
      w: 1000,
      h: 170,
      fontSize: 60,
      fontWeight: 900,
      color: "#FFFFFF",
      align: "left",
      lineHeight: 1.35,
      font: "heading",
    }),
    text({
      text: sub,
      x: M,
      y: 470,
      w: 820,
      h: 60,
      fontSize: 19,
      fontWeight: 500,
      color: "#FFFFFF",
      align: "left",
      lineHeight: 1.7,
      opacity: 0.75,
    }),
  ];
  if (cta) {
    els.push(
      shape({
        shape: "rect",
        x: M,
        y: 562,
        w: 248,
        h: 56,
        fill: "token:accent",
        radius: 28,
        name: "CTAボタン",
      }),
      text({
        text: cta,
        x: M,
        y: 577,
        w: 248,
        h: 28,
        fontSize: 17,
        fontWeight: 700,
        color: "token:brandDark",
        align: "center",
        lineHeight: 1.2,
      }),
    );
  }
  return makeSlide("クロージング", els, "none", "token:brandDark");
}
