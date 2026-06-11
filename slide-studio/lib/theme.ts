import { Theme } from "./types";

export const FONT_OPTIONS: { label: string; value: string }[] = [
  { label: "Noto Sans JP", value: "'Noto Sans JP', sans-serif" },
  { label: "Noto Serif JP", value: "'Noto Serif JP', serif" },
  { label: "Zen Kaku Gothic New", value: "'Zen Kaku Gothic New', sans-serif" },
  { label: "M PLUS Rounded 1c", value: "'M PLUS Rounded 1c', sans-serif" },
  { label: "Shippori Mincho", value: "'Shippori Mincho', serif" },
];

export const COLOR_LABELS: Record<string, string> = {
  brand: "ブランド",
  brandDark: "ブランド(濃)",
  brandSoft: "ブランド(淡)",
  accent: "アクセント",
  bg: "背景",
  surface: "サーフェス",
  ink: "文字",
  muted: "サブテキスト",
  line: "罫線",
};

export const THEME_PRESETS: { name: string; theme: Theme }[] = [
  {
    name: "フォレスト",
    theme: {
      colors: {
        brand: "#0E5E4A",
        brandDark: "#083B2F",
        brandSoft: "#DCEEE7",
        accent: "#F0A01B",
        bg: "#F7F8F6",
        surface: "#FFFFFF",
        ink: "#1B2421",
        muted: "#5D6B66",
        line: "#DDE4E0",
      },
      headingFont: "'Zen Kaku Gothic New', sans-serif",
      bodyFont: "'Noto Sans JP', sans-serif",
    },
  },
  {
    name: "ミッドナイト",
    theme: {
      colors: {
        brand: "#4F7CFF",
        brandDark: "#16204A",
        brandSoft: "#1E2B5E",
        accent: "#5EEAD4",
        bg: "#0D1230",
        surface: "#161D42",
        ink: "#F2F4FF",
        muted: "#9AA5CE",
        line: "#2A3463",
      },
      headingFont: "'Noto Sans JP', sans-serif",
      bodyFont: "'Noto Sans JP', sans-serif",
    },
  },
  {
    name: "エディトリアル",
    theme: {
      colors: {
        brand: "#B4532A",
        brandDark: "#6E2F16",
        brandSoft: "#F4E3D7",
        accent: "#2F5233",
        bg: "#FAF6F0",
        surface: "#FFFFFF",
        ink: "#26201A",
        muted: "#7A6F63",
        line: "#E5DCD0",
      },
      headingFont: "'Shippori Mincho', serif",
      bodyFont: "'Noto Sans JP', sans-serif",
    },
  },
  {
    name: "サクラ",
    theme: {
      colors: {
        brand: "#D6486F",
        brandDark: "#8C2244",
        brandSoft: "#FBE3EA",
        accent: "#3E7CB1",
        bg: "#FFF9FA",
        surface: "#FFFFFF",
        ink: "#33222A",
        muted: "#8A6F79",
        line: "#F0DCE2",
      },
      headingFont: "'M PLUS Rounded 1c', sans-serif",
      bodyFont: "'Noto Sans JP', sans-serif",
    },
  },
];

export const DEFAULT_THEME: Theme = THEME_PRESETS[0].theme;
