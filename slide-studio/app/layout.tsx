import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Slide Studio — AIスライドデザインツール",
  description:
    "AIでスライドを生成し、全パーツをWeb上で編集、リンク付きPDFとして書き出せるデザインツール",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;500;700;800;900&family=Noto+Serif+JP:wght@500;700;900&family=Zen+Kaku+Gothic+New:wght@400;500;700;900&family=M+PLUS+Rounded+1c:wght@400;700;800&family=Shippori+Mincho:wght@500;700;800&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
