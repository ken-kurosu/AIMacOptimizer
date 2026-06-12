import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // ダイナミックrequire/ネイティブバイナリを含むパッケージはバンドルせず
  // ネイティブの require に任せる(PDF書き出し・PDF取り込みでのみ使用)
  serverExternalPackages: ["playwright-core", "pdfjs-dist", "@napi-rs/canvas"],
};

export default nextConfig;
