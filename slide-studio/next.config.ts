import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // playwright-core はダイナミックrequire/fs操作を含むためバンドルせず
  // ネイティブの require に任せる(PDF書き出しでのみ使用)
  serverExternalPackages: ["playwright-core"],
};

export default nextConfig;
