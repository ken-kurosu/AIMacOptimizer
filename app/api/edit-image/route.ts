import sharp from "sharp";
import { readAsset, saveAsset } from "@/lib/assets";
import { uid } from "@/lib/types";
import { editImage, openaiAvailable, pickTransparentImageModels } from "@/lib/openai";

export const maxDuration = 120;

// 画像要素のAI編集。v1は「背景除去(被写体の切り抜き)」のみ。
// アップロード/AI生成済みのアセット(/api/assets/<id>)を対象に、
// gpt-imageのeditsで被写体だけを透過PNGとして切り出す。

const REMOVE_BG_PROMPT =
  "Remove the background completely. Keep only the main subject exactly as it is, " +
  "preserving its colors, details and edges. Fully transparent background. " +
  "No backdrop, no ground shadow. Do not add anything.";

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY が未設定です" }, { status: 400 });
  }
  let src: string;
  try {
    const body = (await req.json()) as { src?: string };
    src = body.src ?? "";
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }
  const assetId = src.match(/^\/api\/assets\/([a-zA-Z0-9_-]+)$/)?.[1];
  if (!assetId) {
    return Response.json(
      { error: "アップロード/AI生成した画像(/api/assets/...)のみ編集できます" },
      { status: 400 },
    );
  }
  const image = await readAsset(assetId);
  if (!image) return Response.json({ error: "画像が見つかりません" }, { status: 404 });

  try {
    // 透過出力に対応するモデル(gpt-image-1系)を新しい順に試す
    const models = await pickTransparentImageModels();
    if (models.length === 0) {
      return Response.json(
        { error: "このAPIキーでは透過対応の画像編集モデルが使えません" },
        { status: 400 },
      );
    }
    let out: Buffer | null = null;
    let lastError: unknown = null;
    for (const model of models) {
      try {
        out = await editImage(model, image, REMOVE_BG_PROMPT, { background: "transparent" });
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (!out) throw lastError ?? new Error("image edit failed");
    const meta = await sharp(out).metadata();
    const url = await saveAsset(`cut-${uid()}`, await sharp(out).png().toBuffer());
    return Response.json({ url, width: meta.width ?? 1024, height: meta.height ?? 1024 });
  } catch (e) {
    console.error("image edit failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "image edit failed" },
      { status: 502 },
    );
  }
}
