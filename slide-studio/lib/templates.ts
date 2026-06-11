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

export function titleSlide(title: string, subtitle: string, meta: string): Slide {
  return makeSlide(
    "タイトル",
    [
      shape({ shape: "rect", x: M, y: 250, w: 88, h: 10, fill: "token:accent" }),
      text({
        text: title,
        x: M,
        y: 282,
        w: 1280 - M * 2,
        h: 170,
        fontSize: 64,
        fontWeight: 900,
        color: "token:ink",
        align: "left",
        lineHeight: 1.25,
        font: "heading",
      }),
      text({
        text: subtitle,
        x: M,
        y: 462,
        w: 1280 - M * 2,
        h: 70,
        fontSize: 24,
        fontWeight: 500,
        color: "token:muted",
        align: "left",
        lineHeight: 1.6,
      }),
      text({
        text: meta,
        x: M,
        y: 620,
        w: 700,
        h: 36,
        fontSize: 16,
        fontWeight: 500,
        color: "token:muted",
        align: "left",
        lineHeight: 1.4,
      }),
    ],
    "mesh",
  );
}

export function sectionSlide(no: string, title: string): Slide {
  return makeSlide(
    `セクション ${no}`,
    [
      text({
        text: no,
        x: M,
        y: 200,
        w: 400,
        h: 160,
        fontSize: 140,
        fontWeight: 900,
        color: "token:brand",
        align: "left",
        lineHeight: 1,
        font: "heading",
        opacity: 0.25,
      }),
      text({
        text: title,
        x: M,
        y: 350,
        w: 1280 - M * 2,
        h: 110,
        fontSize: 48,
        fontWeight: 800,
        color: "token:ink",
        align: "left",
        lineHeight: 1.3,
        font: "heading",
      }),
      shape({ shape: "rect", x: M, y: 480, w: 120, h: 6, fill: "token:accent" }),
    ],
    "blobs",
  );
}

function header(title: string, kicker?: string): SlideElement[] {
  const els: SlideElement[] = [
    text({
      text: title,
      x: M,
      y: kicker ? 96 : 72,
      w: 1280 - M * 2,
      h: 70,
      fontSize: 38,
      fontWeight: 800,
      color: "token:ink",
      align: "left",
      lineHeight: 1.3,
      font: "heading",
    }),
    shape({ shape: "rect", x: M, y: kicker ? 178 : 154, w: 64, h: 6, fill: "token:brand" }),
  ];
  if (kicker) {
    els.unshift(
      text({
        text: kicker,
        x: M,
        y: 60,
        w: 600,
        h: 30,
        fontSize: 16,
        fontWeight: 700,
        color: "token:brand",
        align: "left",
        lineHeight: 1.2,
        letterSpacing: 2,
      }),
    );
  }
  return els;
}

export function bulletsSlide(
  title: string,
  bullets: { head: string; body: string }[],
  kicker?: string,
): Slide {
  const els = header(title, kicker);
  const top = 230;
  const gap = 16;
  const n = Math.min(bullets.length, 4);
  const rowH = Math.min(110, (720 - top - 60 - gap * (n - 1)) / n);
  bullets.slice(0, 4).forEach((b, i) => {
    const y = top + i * (rowH + gap);
    els.push(
      shape({
        shape: "rect",
        x: M,
        y,
        w: 1280 - M * 2,
        h: rowH,
        fill: "token:surface",
        stroke: "token:line",
        strokeWidth: 1,
        radius: 14,
      }),
      shape({ shape: "rect", x: M, y: y, w: 6, h: rowH, fill: "token:brand", radius: 3 }),
      text({
        text: b.head,
        x: M + 36,
        y: y + 16,
        w: 1280 - M * 2 - 72,
        h: 34,
        fontSize: 21,
        fontWeight: 700,
        color: "token:ink",
        align: "left",
        lineHeight: 1.3,
      }),
      text({
        text: b.body,
        x: M + 36,
        y: y + 52,
        w: 1280 - M * 2 - 72,
        h: rowH - 62,
        fontSize: 16,
        fontWeight: 400,
        color: "token:muted",
        align: "left",
        lineHeight: 1.55,
      }),
    );
  });
  return makeSlide(title, els, "dots");
}

export function statsSlide(
  title: string,
  stats: { value: string; label: string }[],
  kicker?: string,
): Slide {
  const els = header(title, kicker);
  const n = Math.min(stats.length, 3);
  const gap = 28;
  const cardW = (1280 - M * 2 - gap * (n - 1)) / n;
  stats.slice(0, 3).forEach((s, i) => {
    const x = M + i * (cardW + gap);
    els.push(
      shape({
        shape: "rect",
        x,
        y: 250,
        w: cardW,
        h: 320,
        fill: "token:surface",
        stroke: "token:line",
        strokeWidth: 1,
        radius: 18,
      }),
      text({
        text: s.value,
        x: x + 24,
        y: 320,
        w: cardW - 48,
        h: 110,
        fontSize: 64,
        fontWeight: 900,
        color: "token:brand",
        align: "center",
        lineHeight: 1.1,
        font: "heading",
      }),
      text({
        text: s.label,
        x: x + 24,
        y: 440,
        w: cardW - 48,
        h: 100,
        fontSize: 17,
        fontWeight: 500,
        color: "token:muted",
        align: "center",
        lineHeight: 1.5,
      }),
    );
  });
  return makeSlide(title, els, "mesh");
}

export function quoteSlide(quote: string, author: string): Slide {
  return makeSlide(
    "メッセージ",
    [
      text({
        text: "“",
        x: M,
        y: 130,
        w: 160,
        h: 160,
        fontSize: 160,
        fontWeight: 900,
        color: "token:brand",
        align: "left",
        lineHeight: 1,
        font: "heading",
        opacity: 0.3,
      }),
      text({
        text: quote,
        x: 160,
        y: 250,
        w: 960,
        h: 220,
        fontSize: 38,
        fontWeight: 700,
        color: "token:ink",
        align: "center",
        lineHeight: 1.6,
        font: "heading",
      }),
      text({
        text: author,
        x: 160,
        y: 500,
        w: 960,
        h: 40,
        fontSize: 18,
        fontWeight: 500,
        color: "token:muted",
        align: "center",
        lineHeight: 1.4,
      }),
    ],
    "frame",
  );
}

export function twoColSlide(
  title: string,
  left: { head: string; body: string },
  right: { head: string; body: string },
  kicker?: string,
): Slide {
  const els = header(title, kicker);
  const colW = (1280 - M * 2 - 32) / 2;
  [left, right].forEach((col, i) => {
    const x = M + i * (colW + 32);
    els.push(
      shape({
        shape: "rect",
        x,
        y: 240,
        w: colW,
        h: 380,
        fill: i === 0 ? "token:brandSoft" : "token:surface",
        stroke: "token:line",
        strokeWidth: i === 0 ? 0 : 1,
        radius: 18,
      }),
      text({
        text: col.head,
        x: x + 36,
        y: 280,
        w: colW - 72,
        h: 44,
        fontSize: 24,
        fontWeight: 800,
        color: i === 0 ? "token:brandDark" : "token:ink",
        align: "left",
        lineHeight: 1.3,
        font: "heading",
      }),
      text({
        text: col.body,
        x: x + 36,
        y: 340,
        w: colW - 72,
        h: 250,
        fontSize: 17,
        fontWeight: 400,
        color: "token:muted",
        align: "left",
        lineHeight: 1.8,
      }),
    );
  });
  return makeSlide(title, els, "none");
}

export function closingSlide(title: string, sub: string, cta?: string): Slide {
  const els: SlideElement[] = [
    text({
      text: title,
      x: 140,
      y: 270,
      w: 1000,
      h: 120,
      fontSize: 56,
      fontWeight: 900,
      color: "#FFFFFF",
      align: "center",
      lineHeight: 1.3,
      font: "heading",
    }),
    text({
      text: sub,
      x: 240,
      y: 410,
      w: 800,
      h: 80,
      fontSize: 20,
      fontWeight: 500,
      color: "#FFFFFF",
      align: "center",
      lineHeight: 1.7,
      opacity: 0.85,
    }),
  ];
  if (cta) {
    els.push(
      shape({
        shape: "rect",
        x: 520,
        y: 520,
        w: 240,
        h: 56,
        fill: "token:accent",
        radius: 28,
      }),
      text({
        text: cta,
        x: 520,
        y: 534,
        w: 240,
        h: 30,
        fontSize: 18,
        fontWeight: 700,
        color: "token:brandDark",
        align: "center",
        lineHeight: 1.2,
      }),
    );
  }
  return makeSlide("クロージング", els, "waves", "token:brandDark");
}
