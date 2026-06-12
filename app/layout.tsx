import type { Metadata } from "next";
import "./globals.css";

// テーマで選べる5書体はセルフホスト(@fontsource)で同一オリジン配信する。
// Google Fonts CDN依存だとオフライン/ブロック環境でフォールバック書体に
// 化けて、ポン出しの見た目が再現しないため
import "@fontsource/noto-sans-jp/400.css";
import "@fontsource/noto-sans-jp/500.css";
import "@fontsource/noto-sans-jp/700.css";
import "@fontsource/noto-sans-jp/800.css";
import "@fontsource/noto-sans-jp/900.css";
import "@fontsource/noto-serif-jp/500.css";
import "@fontsource/noto-serif-jp/700.css";
import "@fontsource/noto-serif-jp/900.css";
import "@fontsource/zen-kaku-gothic-new/400.css";
import "@fontsource/zen-kaku-gothic-new/500.css";
import "@fontsource/zen-kaku-gothic-new/700.css";
import "@fontsource/zen-kaku-gothic-new/900.css";
import "@fontsource/m-plus-rounded-1c/400.css";
import "@fontsource/m-plus-rounded-1c/700.css";
import "@fontsource/m-plus-rounded-1c/800.css";
import "@fontsource/shippori-mincho/500.css";
import "@fontsource/shippori-mincho/700.css";
import "@fontsource/shippori-mincho/800.css";

export const metadata: Metadata = {
  title: "CompDeck — AIスライドデザインツール",
  description:
    "AIでスライドを生成し、全パーツをWeb上で編集、リンク付きPDFとして書き出せるデザインツール",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja">
      <body className="antialiased">{children}</body>
    </html>
  );
}
