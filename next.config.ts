import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // ダイナミックrequire/ネイティブバイナリを含むパッケージはバンドルせず
  // ネイティブの require に任せる(PDF書き出し・PDF取り込みでのみ使用)
  serverExternalPackages: ["playwright-core", "pdfjs-dist", "@napi-rs/canvas"],
  experimental: {
    // proxy.ts(トークン認証)経由のリクエストは本文がメモリにクローンされる。
    // 既定上限は10MBで、超過分は切り詰められてしまう。PDF取り込み(最大40MB)が
    // 途中で切れて「Invalid PDF structure」になるのを防ぐため上限を引き上げる。
    proxyClientMaxBodySize: "48mb",
  },
};

export default nextConfig;
