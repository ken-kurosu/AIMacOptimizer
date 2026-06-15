import { readAsset } from "@/lib/assets";
import { decomposeBackground } from "@/lib/decompose";
import { openaiAvailable } from "@/lib/openai";

export const maxDuration = 300;

// 背景を「無地背景 + 透過モチーフレイヤー群」に分解するAPI。
// 生成直後のデッキは自動で分解済み(lib/decompose.ts)なので、ここは
// 取り込んだ画像や再生成した背景を後から分解し直すための入口。

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY is not configured" }, { status: 400 });
  }
  let src: string;
  let lang: "ja" | "en" = "ja";
  try {
    const body = (await req.json()) as { src?: string; lang?: string };
    src = body.src ?? "";
    if (body.lang === "en") lang = "en";
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }
  const assetId = src.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
  if (!assetId) {
    return Response.json({ error: "only generated backgrounds (/api/assets/...) can be decomposed" }, { status: 400 });
  }
  const image = await readAsset(assetId);
  if (!image) return Response.json({ error: "background image not found" }, { status: 404 });

  try {
    const { background, motifs } = await decomposeBackground(image, lang);
    return Response.json({ background, motifs });
  } catch (e) {
    console.error("decompose failed:", e);
    const msg = e instanceof Error ? e.message : "decompose failed";
    return Response.json({ error: msg }, { status: msg.includes("could not detect") ? 422 : 502 });
  }
}
