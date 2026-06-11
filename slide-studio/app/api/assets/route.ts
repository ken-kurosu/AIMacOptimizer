import sharp from "sharp";
import { saveAsset } from "@/lib/assets";
import { uid } from "@/lib/types";

// 画像アップロード。受け取った画像をpng正規化(既存のアセット配信が.png前提)し、
// 巨大な写真はスライドで使う分には十分な幅2560pxまで縮小して保存する。
const MAX_BYTES = 20 * 1024 * 1024;
const MAX_WIDTH = 2560;

export async function POST(req: Request) {
  const buf = Buffer.from(await req.arrayBuffer());
  if (buf.length === 0) return Response.json({ error: "empty body" }, { status: 400 });
  if (buf.length > MAX_BYTES) {
    return Response.json({ error: "画像が大きすぎます(20MBまで)" }, { status: 413 });
  }
  try {
    let img = sharp(buf, { animated: false });
    const meta = await img.metadata();
    if (!meta.width || !meta.height) throw new Error("not an image");
    let { width, height } = meta;
    if (width > MAX_WIDTH) {
      height = Math.round((height * MAX_WIDTH) / width);
      width = MAX_WIDTH;
      img = img.resize(width, height);
    }
    const id = `up-${uid()}`;
    const url = await saveAsset(id, await img.png().toBuffer());
    return Response.json({ url, width, height });
  } catch {
    return Response.json({ error: "画像として読み込めませんでした" }, { status: 400 });
  }
}
