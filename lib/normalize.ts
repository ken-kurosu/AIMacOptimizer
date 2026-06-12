import {
  BackgroundPreset,
  Deck,
  Slide,
  SlideElement,
  Theme,
  ThemeColors,
  clamp,
  uid,
} from "./types";
import { DEFAULT_THEME, FONT_OPTIONS } from "./theme";

const PRESETS: BackgroundPreset[] = [
  "none",
  "mesh",
  "blobs",
  "diagonal",
  "grid",
  "waves",
  "dots",
  "frame",
  "rings",
  "stripes",
  "corner",
  "sparkle",
];

const HEX = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
const TOKEN = /^token:(brand|brandDark|brandSoft|accent|bg|surface|ink|muted|line)$/;

function color(v: unknown, fallback: string): string {
  if (typeof v === "string" && (HEX.test(v) || TOKEN.test(v))) return v;
  return fallback;
}

function num(v: unknown, fallback: number, min: number, max: number): number {
  const n = typeof v === "number" && Number.isFinite(v) ? v : fallback;
  return clamp(n, min, max);
}

function str(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}

// LLM出力(またはインポートJSON)を安全なDeckに正規化する。
// 多少崩れたJSONでも描画可能な状態に倒す方針。
export function normalizeDeck(raw: unknown): Deck {
  const r = (raw ?? {}) as Record<string, unknown>;
  const theme = normalizeTheme(r.theme);
  const rawSlides = Array.isArray(r.slides) ? r.slides : [];
  const slides = rawSlides.slice(0, 30).map((s, i) => normalizeSlide(s, i));
  if (slides.length === 0) {
    slides.push({
      id: uid(),
      name: "スライド 1",
      background: { color: "token:bg", preset: "mesh" },
      elements: [],
    });
  }
  return {
    id: str(r.id) || uid(),
    title: str(r.title, "無題のプレゼンテーション"),
    theme,
    slides,
  };
}

export function normalizeTheme(raw: unknown): Theme {
  const r = (raw ?? {}) as Record<string, unknown>;
  const rc = (r.colors ?? {}) as Record<string, unknown>;
  const d = DEFAULT_THEME;
  const colors = { ...d.colors };
  for (const k of Object.keys(d.colors) as (keyof ThemeColors)[]) {
    const v = rc[k];
    if (typeof v === "string" && HEX.test(v)) colors[k] = v;
  }
  const fonts = FONT_OPTIONS.map((f) => f.value);
  const pickFont = (v: unknown, fallback: string) => {
    if (typeof v !== "string") return fallback;
    return fonts.find((f) => f === v || f.includes(v)) ?? fallback;
  };
  return {
    colors,
    headingFont: pickFont(r.headingFont, d.headingFont),
    bodyFont: pickFont(r.bodyFont, d.bodyFont),
  };
}

function normalizeSlide(raw: unknown, index: number): Slide {
  const r = (raw ?? {}) as Record<string, unknown>;
  const bg = (r.background ?? {}) as Record<string, unknown>;
  const preset = PRESETS.includes(bg.preset as BackgroundPreset)
    ? (bg.preset as BackgroundPreset)
    : "none";
  const rawEls = Array.isArray(r.elements) ? r.elements : [];
  return {
    id: str(r.id) || uid(),
    name: str(r.name, `スライド ${index + 1}`),
    background: {
      color: color(bg.color, "token:bg"),
      preset,
      image: typeof bg.image === "string" ? bg.image : undefined,
    },
    elements: rawEls
      .slice(0, 40)
      .map(normalizeElement)
      .filter((e): e is SlideElement => e !== null),
    notes: typeof r.notes === "string" ? r.notes : undefined,
  };
}

function normalizeElement(raw: unknown): SlideElement | null {
  const r = (raw ?? {}) as Record<string, unknown>;
  const base = {
    id: str(r.id) || uid(),
    x: num(r.x, 80, -640, 1280),
    y: num(r.y, 80, -360, 720),
    w: num(r.w, 200, 8, 1920),
    h: num(r.h, 60, 4, 1080),
    rotation: r.rotation !== undefined ? num(r.rotation, 0, -180, 180) : undefined,
    opacity: r.opacity !== undefined ? num(r.opacity, 1, 0, 1) : undefined,
    link: typeof r.link === "string" && r.link ? r.link : undefined,
    name: typeof r.name === "string" ? r.name : undefined,
  };
  if (r.type === "text") {
    return {
      ...base,
      type: "text",
      text: str(r.text, "テキスト"),
      fontSize: num(r.fontSize, 18, 8, 240),
      fontWeight: num(r.fontWeight, 400, 100, 900),
      color: color(r.color, "token:ink"),
      align: r.align === "center" || r.align === "right" ? r.align : "left",
      lineHeight: num(r.lineHeight, 1.5, 0.8, 3),
      letterSpacing:
        r.letterSpacing !== undefined ? num(r.letterSpacing, 0, -5, 30) : undefined,
      font: r.font === "heading" || r.font === "body" ? r.font : undefined,
    };
  }
  if (r.type === "shape") {
    return {
      ...base,
      type: "shape",
      shape: r.shape === "ellipse" || r.shape === "line" ? r.shape : "rect",
      fill: color(r.fill, "token:brand"),
      stroke: r.stroke !== undefined ? color(r.stroke, "token:line") : undefined,
      strokeWidth: r.strokeWidth !== undefined ? num(r.strokeWidth, 1, 0, 40) : undefined,
      radius: r.radius !== undefined ? num(r.radius, 0, 0, 360) : undefined,
    };
  }
  if (r.type === "image") {
    const src = str(r.src);
    if (!src) return null;
    return {
      ...base,
      type: "image",
      src,
      fit: r.fit === "contain" ? "contain" : "cover",
      radius: r.radius !== undefined ? num(r.radius, 0, 0, 360) : undefined,
    };
  }
  return null;
}
