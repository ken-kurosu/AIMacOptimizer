// スライドの座標系は 1280x720 固定。エディタ上では CSS transform でスケールする。
export const SLIDE_W = 1280;
export const SLIDE_H = 720;

export interface ThemeColors {
  brand: string;
  brandDark: string;
  brandSoft: string;
  accent: string;
  bg: string;
  surface: string;
  ink: string;
  muted: string;
  line: string;
}

export type ColorKey = keyof ThemeColors;

export interface Theme {
  colors: ThemeColors;
  headingFont: string;
  bodyFont: string;
}

// 色値は "#rrggbb" の生値か "token:brand" のようなテーマトークン参照
export type ColorValue = string;

interface ElBase {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
  rotation?: number;
  opacity?: number;
  link?: string; // 外部URL または "#<slideId>" の内部リンク
  name?: string;
}

export interface TextEl extends ElBase {
  type: "text";
  text: string;
  fontSize: number;
  fontWeight: number;
  color: ColorValue;
  align: "left" | "center" | "right";
  lineHeight: number;
  letterSpacing?: number;
  font?: "heading" | "body";
}

export interface ShapeEl extends ElBase {
  type: "shape";
  shape: "rect" | "ellipse" | "line";
  fill: ColorValue;
  stroke?: ColorValue;
  strokeWidth?: number;
  radius?: number;
}

export interface ImageEl extends ElBase {
  type: "image";
  src: string;
  fit: "cover" | "contain";
  radius?: number;
}

export type SlideElement = TextEl | ShapeEl | ImageEl;

export type BackgroundPreset =
  | "none"
  | "mesh"
  | "blobs"
  | "diagonal"
  | "grid"
  | "waves"
  | "dots"
  | "frame"
  | "rings"
  | "stripes"
  | "corner"
  | "sparkle";

export interface Background {
  color: ColorValue; // ベース色
  preset: BackgroundPreset; // 装飾レイヤー(手続き生成SVG)
  image?: string; // 画像URL(AI生成背景などを後から差し込める)
}

export interface Slide {
  id: string;
  name: string;
  background: Background;
  elements: SlideElement[];
  notes?: string;
}

export interface Deck {
  id: string;
  title: string;
  theme: Theme;
  slides: Slide[];
}

export function uid(): string {
  return Math.random().toString(36).slice(2, 10);
}

export function resolveColor(value: ColorValue, theme: Theme): string {
  if (value?.startsWith("token:")) {
    const key = value.slice(6) as ColorKey;
    return theme.colors[key] ?? "#000000";
  }
  return value;
}

export function clamp(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, n));
}
